#!/usr/bin/env python3
"""Pick the best local MLX model for this Mac's RAM and report context headroom.

Reads real RAM from sysctl, reproduces oMLX's memory-ceiling formula, and for each
candidate model computes the largest context that actually survives prefill — not
just the largest that can be configured. Those two differ, which is the whole point
of this script: oMLX will happily accept a 48K setting and then abort mid-prefill.

Usage:
  omlx-fit.py                 # table of every candidate + verdict
  omlx-fit.py --ram 24        # pretend this machine has 24 GB
  omlx-fit.py --json          # machine-readable
"""

import argparse
import json
import subprocess
import sys

GIB = 1024**3

# --- oMLX ceiling constants, read from omlx/process_memory_enforcer.py -------
SMALL_SYSTEM_THRESHOLD_GIB = 24  # below this, reserve is flat regardless of tier
SMALL_SYSTEM_RESERVE_GIB = 4.0
TIER_RESERVE_GIB = {"safe": 8.0, "balanced": 6.0, "aggressive": 4.0, "custom": 2.0}
HARD_WATERMARK = 0.95  # abort threshold as a fraction of the ceiling
METAL_CAP_FRACTION = 0.74  # Metal recommendedMaxWorkingSetSize, measured 11.84/16

# Prefill activation cost per 1K context tokens, scaled by layers/32.
# Back-calculated from measured peaks on a 16 GB M2, both models L=32 / kv=4 / hd=256:
#   Qwen3.5-9B: aborted at 11.3 GB on a 37.8K prompt -> 0.118 GiB/1K activation
#   Qwen3.5-4B: completed a 37.8K prompt at 9.25 GB  -> 0.136 GiB/1K activation
# The two agree despite hidden_size differing 4096 vs 2560, so activation is scaled by
# LAYER COUNT, not hidden_size. An earlier version scaled by hidden_size and
# underestimated the 4B by ~2 GiB. The layers/32 scaling is inferred, not measured —
# both calibration models have 32 layers — so treat deep models (the 64-layer 27B) as
# rough. Takes the conservative end of the measured range.
# NOTE: this predicts the LIMIT well (4B: 49K predicted vs 48.3K verified; 9B: 33K vs
# 31.5K verified) but OVERSTATES peak usage — the 4B's verified 48.3K run peaked at only
# 5.80 GB against an 11.0 GiB budget. oMLX's guard adaptively expands to fill available
# memory and throttles chunk size as it tightens, so peak is not a fixed function of
# context. Read the "@48K bud" column as a sizing budget, not a prediction of RSS.
# Measurements also shift with machine state: the same 4B prompt took 420s at 9.25 GB
# with 4.4 GB of swap in use, and 143s at 5.80 GB on a clean machine.
# This activation term dominates; the KV cache is comparatively small.
PREFILL_GIB_PER_1K_PER_32L = 0.136

CLAUDE_CODE_MIN_CONTEXT = 48 * 1024  # integrations/claude.py refuses below this

# Verified MLX repos. weights_gib = actual .safetensors total from the HF tree API.
MODELS = [
    {
        "id": "mlx-community/Qwen3.5-4B-MLX-4bit",
        "label": "Qwen3.5-4B 4-bit",
        "weights_gib": 2.83,
        "layers": 32, "kv_heads": 4, "head_dim": 256, "hidden": 2560,
        "drafter": "z-lab/Qwen3.5-4B-DFlash",
        "quality": 1,
        # measured on 16 GB M2: 48.3K prompt completed in 143s at 338 tok/s prefill,
        # peak 5.80 GB, chunk throttled only 2048->1792. Clears the Claude Code gate.
        "verified_ctx": 48260, "verified_on_gib": 16,
    },
    {
        "id": "mlx-community/Qwen3.5-9B-MLX-4bit",
        "label": "Qwen3.5-9B 4-bit",
        "weights_gib": 5.54,
        "layers": 32, "kv_heads": 4, "head_dim": 256, "hidden": 4096,
        "drafter": "z-lab/Qwen3.5-9B-DFlash",
        "quality": 2,
        # measured on 16 GB M2: 31.5K OK; 37.8K aborted at 11.3 GB
        "verified_ctx": 31516, "verified_on_gib": 16,
        # VLM-typed: the non-DFlash VLM engine loads the vision tower too (5.68 GiB
        # resident measured). DFlash's text-only path loaded only 3.39 GiB.
    },
    {
        "id": "lukaskremla/Qwen3.8-27B-3bit-MLX-TextOnly",
        "label": "Qwen3.8-27B 3-bit (text-only)",
        "weights_gib": 10.96,
        "layers": 64, "kv_heads": 4, "head_dim": 256, "hidden": 5120,
        "drafter": None,  # no DFlash/DFlash2 drafter below 4-bit 27B
        "quality": 3,
    },
]


def system_ram_gib() -> float:
    out = subprocess.run(
        ["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, check=True
    )
    return int(out.stdout.strip()) / GIB


def usable_budget_gib(ram_gib: float, tier: str = "balanced") -> dict:
    """Reproduce oMLX's abort threshold. Returns the binding constraint too."""
    if ram_gib < SMALL_SYSTEM_THRESHOLD_GIB:
        reserve = SMALL_SYSTEM_RESERVE_GIB  # tier is ignored below 24 GiB
        tier_applies = False
    else:
        reserve = TIER_RESERVE_GIB[tier]
        tier_applies = True
    static = ram_gib - reserve
    metal = ram_gib * METAL_CAP_FRACTION
    ceiling = min(static, metal)
    return {
        "static_ceiling_gib": static,
        "metal_cap_gib": metal,
        "ceiling_gib": ceiling,
        "usable_gib": ceiling * HARD_WATERMARK,
        "binding": "static reserve" if static < metal else "Metal working set",
        "tier_applies": tier_applies,
        "reserve_gib": reserve,
    }


def kv_gib_per_1k(m: dict, kv_bits: int) -> float:
    """KV cache cost per 1000 context tokens. 2 = one K plus one V tensor."""
    bytes_per_elem = kv_bits / 8
    per_token = 2 * m["layers"] * m["kv_heads"] * m["head_dim"] * bytes_per_elem
    return per_token * 1000 / GIB


def required_gib(m: dict, ctx: int, kv_bits: int) -> float:
    per_1k = kv_gib_per_1k(m, kv_bits) + PREFILL_GIB_PER_1K_PER_32L * (m["layers"] / 32)
    return m["weights_gib"] + per_1k * (ctx / 1000)


def max_context(m: dict, usable: float, kv_bits: int) -> int:
    """Largest context whose predicted peak stays under the abort threshold."""
    per_1k = kv_gib_per_1k(m, kv_bits) + PREFILL_GIB_PER_1K_PER_32L * (m["layers"] / 32)
    room = usable - m["weights_gib"]
    if room <= 0:
        return 0
    return int(room / per_1k * 1000)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--ram", type=float, help="override detected RAM, in GB")
    p.add_argument("--tier", default="balanced", choices=sorted(TIER_RESERVE_GIB))
    p.add_argument("--kv-bits", type=int, default=4, choices=[4, 8, 16],
                   help="4 = turboquant_kv_enabled (recommended)")
    p.add_argument("--json", action="store_true")
    a = p.parse_args()

    ram = a.ram if a.ram else system_ram_gib()
    b = usable_budget_gib(ram, a.tier)
    usable = b["usable_gib"]

    rows = []
    for m in MODELS:
        cap = max_context(m, usable, a.kv_bits)
        rows.append({
            "id": m["id"],
            "label": m["label"],
            "weights_gib": m["weights_gib"],
            "max_context": cap,
            "fits_at_all": cap >= 4096,
            "claude_code_ready": cap >= CLAUDE_CODE_MIN_CONTEXT,
            "at_48k_gib": round(required_gib(m, CLAUDE_CODE_MIN_CONTEXT, a.kv_bits), 2),
            "drafter": m["drafter"],
            "quality": m["quality"],
            "verified_ctx": m.get("verified_ctx"),
            "verified_on_gib": m.get("verified_on_gib"),
        })

    ready = [r for r in rows if r["claude_code_ready"]]
    usable_rows = [r for r in rows if r["fits_at_all"]]
    # Best = highest quality that clears Claude Code's gate; else best that runs at all.
    best = max(ready or usable_rows, key=lambda r: r["quality"]) if usable_rows else None

    if a.json:
        print(json.dumps({"ram_gib": ram, "budget": b, "models": rows,
                          "best": best, "kv_bits": a.kv_bits}, indent=2))
        return 0

    print(f"RAM detected:      {ram:.0f} GB")
    print(f"oMLX ceiling:      {b['ceiling_gib']:.2f} GiB "
          f"(binding: {b['binding']}; reserve {b['reserve_gib']:.0f} GiB)")
    if not b["tier_applies"]:
        print("                   NOTE: under 24 GB the reserve is flat — "
              "changing memory_guard_tier will NOT help")
    print(f"Abort threshold:   {usable:.2f} GiB  <- everything must fit under this")
    print(f"KV quantization:   {a.kv_bits}-bit"
          f"{' (turboquant_kv_enabled)' if a.kv_bits == 4 else ''}\n")

    print(f"{'model':<30}{'weights':>9}{'pred ctx':>10}{'verified':>10}{'@48K bud':>10}  verdict")
    print("-" * 90)
    for r in sorted(rows, key=lambda x: x["quality"]):
        ctx = f"{r['max_context']/1000:.0f}K" if r["fits_at_all"] else "—"
        if not r["fits_at_all"]:
            verdict = "does not fit"
        elif r["claude_code_ready"]:
            verdict = "Claude Code ready"
        else:
            verdict = f"too small for Claude Code (needs 48K)"
        v = r["verified_ctx"]
        # Only count as verified when proven on a machine no larger than this one.
        proven = v and r["verified_on_gib"] and r["verified_on_gib"] <= ram
        vtxt = f"{v/1000:.1f}K" if proven else ("—" if not v else f"({v/1000:.1f}K)")
        print(f"{r['label']:<30}{r['weights_gib']:>7.2f}G{ctx:>10}{vtxt:>10}"
              f"{r['at_48k_gib']:>9.1f}G  {verdict}")

    print()
    if best is None:
        print("VERDICT: no candidate model fits this machine.")
        return 1

    if best["claude_code_ready"]:
        print(f"READY TO SET UP — best pick: {best['id']}")
        print(f"  predicted max context ~{best['max_context']/1000:.0f}K, "
              "clears Claude Code's 48K gate.")
        v = best["verified_ctx"]
        if v and v < CLAUDE_CODE_MIN_CONTEXT * 0.95:
            print(f"  CAUTION: only verified to {v/1000:.1f}K tokens on real hardware — 48K")
            print("  claim is a prediction. Prove it with a full-size prompt (SKILL.md")
            print("  step 5 check 3) before telling the user Claude Code will hold up.")
        elif v:
            print(f"  VERIFIED on hardware: a {v/1000:.1f}K-token prompt completed "
                  f"(gate is {CLAUDE_CODE_MIN_CONTEXT/1000:.1f}K).")
        print(f"  Next: set it up for Claude Code and DTF (see SKILL.md step 4).")
    else:
        print(f"BEST AVAILABLE: {best['id']} at ~{best['max_context'] // 1024}K context")
        print("  NOT Claude Code ready — its gate needs 48K and this would abort")
        print("  mid-prefill on real prompts. Options:")
        smaller = [r for r in rows if r["claude_code_ready"]]
        if smaller:
            alt = max(smaller, key=lambda r: r["quality"])
            print(f"   - drop to {alt['id']} (~{alt['max_context'] // 1024}K) "
                  "to get a working Claude Code setup")
        print("   - keep this model for the OpenAI endpoint / admin chat only")
        print(f"   - or move to a machine with more RAM "
              f"(try: {sys.argv[0]} --ram 24)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
