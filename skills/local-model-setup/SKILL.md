---
name: local-model-setup
description: Set up a local LLM on this Mac via oMLX — sizes the machine's RAM, picks the best model that actually fits, checks whether it clears the context gate, and wires it into Claude Code and DTF. Use when the user wants to run a model locally, asks which local model their Mac can handle, mentions oMLX / MLX / DFlash / speculative decoding, or wants a local model as a Claude Code backend.
user_invocable: true
---

# Local Model Setup (oMLX on Apple Silicon)

Gets a local model serving on this Mac and, if it's big enough to be useful, wired
into Claude Code. Built from a measured setup on a 16 GB M2 — see `reference.md` for
the benchmark data and the mistakes worth not repeating.

**The one thing this skill exists to prevent:** oMLX lets you *configure* a context
window far larger than the machine can actually prefill. It accepts the setting, then
aborts mid-request minutes later. Always size before you promise anything.

## Step 1 — Size the machine first

```bash
python3 ~/.claude/skills/local-model-setup/scripts/omlx-fit.py
```

Prints detected RAM, oMLX's real abort threshold, and per-model max context with a
verdict. It reproduces oMLX's ceiling formula and is calibrated against measured
prefill aborts, so trust it over parameter-count rules of thumb.

Read the verdict literally:

- **"READY TO SET UP"** — that model clears Claude Code's 48K gate. Continue to step 2.
- **"too small for Claude Code"** — it will run, but not as a Claude Code backend.
  Either drop to the smaller model the script names, or use it via the OpenAI
  endpoint only. Say this plainly to the user before setting anything up; do not
  configure 48K to satisfy the gate and call it working.
- **"does not fit"** — do not download it. Check `--ram 24` / `--ram 32` to tell the
  user what hardware would be needed.

Then confirm the pick with the user before downloading gigabytes.

## Step 2 — Free the memory

oMLX's ceiling is dynamic. Docker Desktop is usually the problem — a default VM
allocation can be most of a 16 GB machine, and it dropped the observed ceiling from
10.4 GiB to 3.9 GiB.

```bash
docker ps -q | wc -l                              # containers up?
docker info --format '{{.MemTotal}}' 2>/dev/null  # VM allocation
```

Ask the user to stop Docker; never stop their containers yourself. On a ≤16 GB
machine a local model and a Docker dev stack cannot coexist — say so up front.

Note: under 24 GB the memory reserve is flat, so **changing `memory_guard_tier` does
not raise the ceiling.** Don't offer it as a fix.

## Step 3 — Install, download, configure

```bash
# install (skip if `omlx --version` works)
brew tap jundot/omlx https://github.com/jundot/omlx
brew install jundot/omlx/omlx     # ~10 min, 1.6 GB
omlx start --timeout 120

# admin API needs a key + session cookie before anything else works
KEY="omlx-$(python3 -c 'import secrets;print(secrets.token_hex(20))')"
curl -s -X POST localhost:8000/admin/api/setup-api-key -H 'Content-Type: application/json' \
  -d "{\"api_key\":\"$KEY\",\"api_key_confirm\":\"$KEY\"}"      # both fields required
curl -s -c /tmp/omlx.cookies -X POST localhost:8000/admin/api/login \
  -H 'Content-Type: application/json' -d "{\"api_key\":\"$KEY\"}"

# download (repo id from step 1)
curl -s -b /tmp/omlx.cookies -X POST localhost:8000/admin/api/hf/download \
  -H 'Content-Type: application/json' -d '{"repo_id":"<MODEL>"}'
curl -s -b /tmp/omlx.cookies localhost:8000/admin/api/hf/tasks   # poll; needs a real sleep
```

The key is persisted to `~/.omlx/settings.json`, which is where `omlx launch` reads
it from — the user never needs to pass it again.

Then apply settings. `<ID>` is the short model id from `/admin/api/models`, not the
repo path. Set the context to what step 1 said fits, **not** what you wish it were:

```bash
curl -s -b /tmp/omlx.cookies -X PUT localhost:8000/admin/api/models/<ID>/settings \
 -H 'Content-Type: application/json' -d '{
   "max_context_window": <FROM_STEP_1>,
   "turboquant_kv_enabled": true, "turboquant_kv_bits": 4,
   "enable_thinking": false, "reasoning_parser": "qwen",
   "is_default": true }'
curl -s -b /tmp/omlx.cookies -X POST localhost:8000/admin/api/models/<ID>/load
```

Why each of those matters:

- `turboquant_kv_*` — a 4-bit KV cache is 4× smaller than fp16 and cost no measurable
  speed. Without it, long contexts don't fit.
- `enable_thinking: false` + `reasoning_parser` — Qwen otherwise emits raw
  `Thinking Process:` prose into visible output, which pollutes every reply.
- **Do not enable DFlash without benchmarking it** (step 5). It was a 20–48% *slowdown*
  on an M2 base.

## Step 4 — Wire Claude Code and DTF

Only once step 1 said the model clears 48K.

```bash
omlx launch claude --model <ID>
```

This injects `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` into the child process
only — it writes nothing to `~/.claude`, so the user's normal setup is untouched.
`--opus` / `--sonnet` / `--haiku` map individual tiers if you want only some traffic
local.

Shell aliases (added to `~/.zshrc`; back up before editing, and re-add after any
dotfile reset):

```bash
alias claude-local='omlx launch claude --model Qwen3.5-4B-MLX-4bit'
alias omlx-status=' ... omlx-down.sh --status'
alias omlx-stop='  ... omlx-down.sh'
alias omlx-fit='   ... omlx-fit.py'
alias omlx-verify=' ... omlx-verify.sh'
```

**Never export `ANTHROPIC_BASE_URL` globally.** It would silently route every `claude`
session on the machine to the local model, real work included. A separate command is the
only safe shape. The corollary users trip over: because the integration is env-var-only
and writes nothing to `~/.claude`, the local model exists *only* inside a window opened
this way — close the window and it's gone, and a normal `claude` never sees it.

**DTF:** be honest about what's viable. At local decode speeds (~17 tok/s) and
prefill of 100–220 tok/s, no DTF phase that reads the convention docs is realistic —
architecture, review, and ticket analysis all depend on context this can't hold, and
would degrade in quality, not just speed. Good local candidates are small mechanical
jobs off the critical path: drafting a commit message from a diff, summarizing a CI
log. Propose one of those as a standalone script and get confirmation before editing
any DTF command or agent — those live in shared config.

## Step 5 — Verify from a clean state

```bash
scripts/omlx-verify.sh <ID>                  # state gate + throughput + tool calling
scripts/omlx-verify.sh <ID> --full           # ... plus a full-size context test (slow)
scripts/omlx-verify.sh <ID> --full --reset   # reload first to clear pooled Metal buffers
scripts/omlx-verify.sh <ID> --state          # just the state check
```

**The state gate is the point.** It refuses to benchmark while swap > 1 GB, the
compressor is > 3 GiB, or Docker containers are up — because the same model on the same
prompt measured **420 s / 9.25 GB peak with 4.4 GB of swap hot, and 143 s / 5.80 GB on a
clean machine.** A 3x error from machine state alone. If you benchmark dirty you will
draw the wrong conclusion and write it into the docs, which is exactly what happened
here. `--force` exists, but then label the result unreliable.

To get clean: stop Docker, `omlx-down.sh --models` to unload and let swap settle, then
reload. `--reset` does the reload for you.

The three checks and why each earns its place:

1. **Throughput** — from `usage.total_time`, server-measured, after a warmup call.
2. **Tool calling with LOOSE phrasing.** A coaxed prompt ("use the read_file tool")
   passes even on a model that won't pick a tool unprompted — the 4B refused
   "using the available tool" while the 9B complied, then managed 3/3 when coaxed.
   Agentic loops depend on unprompted selection, so the loose prompt is the real test.
   A `WEAK` verdict means Claude Code will stall or need hand-holding.
3. **Full-size context** at ~98% of the configured window. You cannot send more than
   `max_context_window`, so this is the strongest available proof. A configured window
   proves nothing on its own — this is the check that gets skipped, and skipping it is
   how a "48K-ready" claim turns out to abort mid-prefill.

Always record a figure together with the state block the script prints. A number
without its machine state is not a measurement.

If the user wants DFlash, benchmark it with `dflash_enabled` true and false, reloading
between each, and report both. Every variant measured slower on an M2 base.

## Step 5b — What to actually test in chat

Benchmarks say it's alive; these say whether it's *useful*. Run them in ascending order
and stop where it breaks — that tells you the real ceiling better than any token count.

1. **Recall, no tools** — "What does `Array.prototype.flatMap` do?" Establishes baseline
   coherence. If this is shaky, nothing else matters.
2. **Single-file generation** — "Write a TypeScript debounce that preserves the return
   type." A 4B should manage this. Check it compiles mentally: generics right, no
   invented APIs.
3. **Unprompted tool use** — "What files are in this directory?" The model must *choose*
   to call a tool without being told to. This is where small models fail and where
   agentic use lives or dies. Run it several times; the 4B is non-deterministic here.
4. **Read-then-reason** — "Read package.json and tell me which test runner this uses."
   Two steps: one tool call, then reasoning over real output.
5. **Multi-step edit** — "Add a `--verbose` flag to <small script> and show the diff."
   Requires read, plan, write. Expect this to be the first thing that struggles.
6. **Follow a convention** — point it at a real convention doc and ask it to apply one
   rule. Tests instruction-following under a large context, which is the actual failure
   mode for local models on this repo.

What to watch for beyond right/wrong answers:

- **Invented APIs / hallucinated file paths** — the classic small-model tell.
- **Declining a tool it has** ("I cannot access your filesystem") — capability is there,
  the decision isn't.
- **Ignoring half a multi-part instruction** — the practical ceiling for a 4B.
- **`Thinking Process:` leaking into replies** — means `enable_thinking: false` isn't
  holding through that request shape; report it, don't work around it.

Honest expectation for a 4B: solid at 1-2, usable at 3-4 with retries, unreliable at
5-6. That maps to "single-file, well-specified, low-stakes work" — which is exactly what
the model itself said when asked.

## Step 6 — Cleanup (do not leave a model resident)

A loaded model holds 3–6 GiB indefinitely, and oMLX ships with idle unload
**disabled** (`idle_timeout_seconds: null`), so nothing reclaims it on its own. On a
16 GB machine that silently starves everything else — this is the most likely way the
setup becomes a nuisance rather than a toy.

```bash
scripts/omlx-down.sh --status     # what's loaded, what it costs, is idle unload armed
scripts/omlx-down.sh --idle 900   # self-cleaner: models drop after 15 min idle
scripts/omlx-down.sh --models     # unload now, keep the server up
scripts/omlx-down.sh              # full stop: unload + stop service + verify port free
scripts/omlx-down.sh --disable    # ... and stop it coming back at login
```

**Arm `--idle` as part of setup**, not as an afterthought — it's the difference
between a server that gets out of the way and one the user has to remember. 60s is the
minimum oMLX accepts. Re-loading afterwards costs ~1 minute, which is a fair trade
against holding gigabytes.

Reach for the full stop before starting Docker or any other memory-hungry work. The
script verifies the port is actually free afterwards rather than trusting
`brew services stop`, which can fail quietly.

## Reference

`reference.md` — measured benchmarks, the memory formula with its constants, DFlash
findings, and the model/drafter compatibility table.
