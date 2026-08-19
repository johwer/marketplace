# Local Model Reference — measured data

All numbers below were measured on **MacBook Pro, Apple M2 (8 cores: 4P+4E), 16 GB RAM,
macOS 26.6.1**, oMLX **0.6.3rc1**, on 2026-08-19. Treat them as anchors for that
machine, and re-measure on new hardware rather than extrapolating.

## Throughput — Qwen3.5-9B-MLX-4bit

250-token completions at `temperature: 0`, warm, timed by `usage.total_time`:

| Config | tok/s |
|---|---|
| No DFlash (baseline) | **17.8** |
| No DFlash, 4-bit KV (48K *configured*, short prompt) | 17.4 |
| DFlash, `verify=adaptive`, int4 drafter | 14.2 |
| DFlash, `verify=adaptive`, unquantized drafter | 11.9 |
| DFlash, `verify=dflash` (fixed), int4 drafter | 9.2 |

**DFlash speculative decoding is a net loss on an M2 base — leave it off.** Every
variant lost to plain autoregressive decoding. The drafter's extra compute per cycle
costs more than verification saves on a chip with 8 GPU cores and ~100 GB/s of
bandwidth; the published 2.7–4.4× figures assume far more compute relative to
bandwidth. 4-bit KV quantization cost essentially nothing (17.4 vs 17.8), so always
enable it.

Prefill is much slower than decode and is usually the real cost:

| Prompt | Wall time | Prefill |
|---|---|---|
| 13.5K tokens | 135 s | ~100 tok/s |
| 20.7K tokens | 129 s | ~161 tok/s |
| 31.5K tokens | 144 s | ~219 tok/s |

A full prompt costs **minutes before the first token**. This, more than tok/s, is what
makes a local model impractical for agentic coding loops on this hardware.

## Context limits — measured, 16 GB

| Prompt size | Result |
|---|---|
| 31.5K | OK |
| ~36K | Rejected by the pre-chunk prefill guard |
| 45K | Aborted mid-prefill at 11.3 GB vs an 11.2 GB threshold, after 6 minutes |

So the practical ceiling is **~32K**, even though `max_context_window: 49152` was
accepted without complaint. **The KV cache is not the binding constraint** — at 48K it
is only 1.50 GiB at 4 bits. Prefill activation peak is what blows the budget, which is
why aborts happen mid-request rather than at load.

## The memory ceiling formula

From `omlx/process_memory_enforcer.py`:

```
reserve  = 4 GiB                       if RAM < 24 GiB   (flat — tier is IGNORED)
         = {safe:8, balanced:6, aggressive:4, custom:2}  otherwise
ceiling  = min(RAM - reserve, metal_cap)      # metal_cap ~= 0.74 x RAM
abort at = 0.95 x ceiling
```

On 16 GB: ceiling 11.84 GiB (Metal-bound), abort threshold ~11.2 GiB — matching the
observed abort exactly. **Below 24 GB, raising `memory_guard_tier` does nothing**,
because the reserve is flat; don't offer it as a fix.

The dynamic term is `free + inactive + active × ratio`, recomputed per call, so the
ceiling moves with system load. Observed: **3.9 GiB with Docker running, 10.4–11.8 GiB
with it stopped.** Docker Desktop had allocated 12.79 GB of 16 to its VM.

### Minimum RAM for a real 48K context

| RAM | Abort threshold | 9B at 48K (needs ~13.4 GiB) |
|---|---|---|
| 16 GB | 11.25 GiB | No |
| 24 GB | 16.87 GiB | Yes |
| 32 GB | 24.70 GiB | Yes, with room for Docker |

**24 GB is the minimum for a dependable 48K context** on a 9B — which independently
matches the "24 GB fit-first minimum" published for these models.

## Model / drafter compatibility

DFlash needs a drafter trained against that exact target, so you cannot pair an
arbitrary mlx-community model with an arbitrary drafter.

| Target | 4-bit weights | Drafter |
|---|---|---|
| `mlx-community/Qwen3.5-4B-MLX-4bit` | 2.83 GiB | `z-lab/Qwen3.5-4B-DFlash` (1.18 GiB) |
| `mlx-community/Qwen3.5-9B-MLX-4bit` | 5.54 GiB | `z-lab/Qwen3.5-9B-DFlash` (2.41 GiB) |
| `mlx-community/Qwen3.8-27B-4bit` | 14.95 GiB | `incoai/Qwen3.8-27B-DFlash2` (3.58 GiB) |
| `lukaskremla/Qwen3.8-27B-3bit-MLX-TextOnly` | 10.96 GiB | none below 4-bit 27B |

**DFlash 2** exists only for Qwen3.8-27B and Muse Glimmer 30B — both ~15 GiB at 4-bit,
so DFlash 2 is unreachable on any 16 GB machine. Smaller targets have original DFlash
drafters only: `verify_mode: dflash`/`adaptive`, block size 16 (not 5).

**GGUF cannot be used with oMLX at all** — verified by inspecting the installed
package, there is no GGUF code path. Unsloth dynamic quants (`UD-Q2_K_XL` etc.) are
llama.cpp-only, regardless of how well their size would fit. `incoai/Qwen3.8-27B-DFlash2-GGUF`
exists for a llama.cpp setup, but that's a different runtime.

Also: **Qwen3.5-9B registers as `model_type: vlm`.** DFlash handles that natively
(text-only drafter, images routed to the VLM fallback engine) and loaded only 3.39 GiB;
the plain VLM engine loaded the full 5.68 GiB including the vision tower. So DFlash
used *less* memory while being slower.

## Gotchas that cost time

- `/admin/api/setup-api-key` requires **both** `api_key` and `api_key_confirm`. Login
  fails with "No API key configured" until setup has run once.
- All `/admin/api/*` calls need the **session cookie** from `/admin/api/login`, not a
  bearer token. `skip_api_key_verification` bypasses admin auth entirely — don't.
- Model ids in `/admin/api/models` are **short names** (`Qwen3.5-9B-MLX-4bit`), not
  repo paths. Settings endpoints want the short id; `dflash_draft_model` wants the repo id.
- `health.engine_pool.current_model_memory` reports **load-time** residency and does
  not track prefill peak — it read 5.82 GiB while the process guard saw 11.3 GB. Never
  use it to judge whether a context size fits.
- `omlx launch claude` refuses any model configured under **48K** context
  (`Claude Code requires at least 48K context`).
- `mtp_enabled` is mutually exclusive with `dflash_enabled`.
- `/admin/api/hf/tasks` reports a **stale `downloaded_size`/`progress`** — it sat at
  26 MB while 1.1 GB was already on disk, and `progress` briefly read 380%. Poll
  `status` for completion and `du -sh ~/.omlx/models/<org>/<repo>` for real progress.
- The brew service **restarts at login**; `brew services stop jundot/omlx/omlx` to disable.
- Changing `max_context_window`, KV bits, or DFlash settings requires an
  unload + load cycle to take effect.

## How this was installed

Homebrew formula (a signed/notarized `.dmg` with a menu-bar GUI is the alternative —
see the Releases page under Sources). The brew route gives the CLI plus the same
`/admin` web dashboard, which is all this skill drives:

```bash
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx      # ~10 min, builds a venv, 35,941 files / 1.6 GB
omlx start --timeout 120            # managed background service via brew services
```

Landed as **0.6.3rc1** at `/opt/homebrew/opt/omlx/bin/omlx`, serving
`http://localhost:8000`, with state under `~/.omlx/` (`settings.json`, `models/`,
`logs/server.log`). Requires macOS 15.0+ and Apple Silicon M1–M4.

The service is registered to **restart at login**; disable with
`brew services stop jundot/omlx/omlx`.

Models were pulled through oMLX's own downloader (`/admin/api/hf/download`) rather
than `hf` CLI, so they land in `~/.omlx/models/<org>/<repo>` and are auto-discovered.
`omlx serve <repo-id>` also downloads on demand.

## Sources

Consulted while building this, with what each was actually good for:

- **oMLX repo** — <https://github.com/jundot/omlx> — install routes, feature overview,
  endpoint list. Releases: <https://github.com/jundot/omlx/releases>
- **oMLX DFlash integration notes** —
  <https://github.com/jundot/omlx/blob/main/docs/experimental/dflash_mlx_integration.md>
  — the per-model DFlash settings, block-diffusion mechanics, and the
  one-request-at-a-time caveat (no continuous batching under the DFlash engine).
- **Inco AI, "DFlash 2: Keep Drafting Parallel"** — <https://inco.ai/blog/dflash2/> —
  DFlash 2's claims and, critically, that only two drafters shipped (Qwen3.8-27B and
  Muse Glimmer 30B), which is why DFlash 2 is unreachable under 16 GB.
- **DFlash paper + reference impl** — <https://arxiv.org/abs/2602.06036> and
  <https://github.com/z-lab/dflash> — where the `z-lab/*-DFlash` drafters come from.
- **LMSYS on next-gen speculative decoding** —
  <https://www.lmsys.org/blog/2026-06-15-next-generation-speculative-decoding-dflash-v2/>
- **Qwen3.8-27B hardware requirements** —
  <https://kingy.ai/blog/qwen3-8-27b-local-hardware-requirements/> — the
  `UD-Q2_K_XL` = 10.68 GB figure and the "24 GB fit-first minimum" verdict, which our
  own measurements independently reproduced. Note its numbers are GGUF/llama.cpp and
  do not transfer to oMLX.
- **The installed package itself** —
  `/opt/homebrew/opt/omlx/libexec/lib/python3.11/site-packages/omlx/` — the most
  reliable source by a wide margin. `process_memory_enforcer.py` for the ceiling
  constants, `model_settings.py` for every setting's meaning, `integrations/claude.py`
  for the 48K gate, and a `grep` for `gguf` proving there is no GGUF path. Docs and
  blogs disagreed with the code more than once; the code won.

## Endpoints

- OpenAI-compatible: `POST /v1/chat/completions` (bearer auth)
- Anthropic-compatible: `POST /v1/messages` (`x-api-key` + `anthropic-version`)
- Admin UI: `/admin` — model manager, benchmarks, chat
- Health: `/health` (unauthenticated)
