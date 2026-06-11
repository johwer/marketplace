# Docker Fast — Start/Restart the Repo Stack Without the OOM

Bring the Repo docker stack up **fast and safely**, avoiding the full-stack parallel rebuild that OOMs Docker Desktop (exit 137) and triggers the R1 EF-migration zombie. Encodes the daily-workflow recommendations from **NOVA-1613 (PROJ-1613 "Make docker fast again")** — whose Dockerfile-level wins (NuGet cache mount + publish-only) are *already merged*; this command adds the two missing pieces (parallel cap + service "categories") at the **orchestration layer only — no repo files are edited, nothing is created on disk**.

## The core rule (why this exists)

**NEVER run `docker compose up -d --build` with no service args.** That rebuilds all ~12 .NET services in parallel (6–12 GB RAM → SIGKILL) and races concurrent EF migrations (R1 zombie at 100% CPU). Instead: keep infra + already-built images running, and only `--build` the specific service(s) you changed, with `COMPOSE_PARALLEL_LIMIT` capped.

## Input

$ARGUMENTS

Modes (first token):
- *(empty)* / `up` — ensure infra is up, then start **all backend** services detached, **no build** (reuses existing images). The everyday "just run it" + the recovery I'd reach for first.
- `recover` / `restart` — `docker compose down --remove-orphans` then `up -d` (no build). Fixes a broken half-up state (e.g. infra SIGKILLed overnight, workers crash-looping). **Volumes/data preserved** (never `-v`).
- `infra` — only `postgres redis rabbitmq localstack localstack-init` (+ `tools` if `--tools`).
- `<domain>` — one or more of `service-c service-a service-b service-d service-e` → starts that domain's api+workers **plus infra** (no build unless `--build`).
- `<service> [<service>…]` — exact compose service name(s) → ensure infra, then start just those.
- `down` — stop the stack cleanly (keeps volumes). `down --hard` adds `--remove-orphans`.
- `bench` — **benchmark the build.** Timed `COMPOSE_BAKE=true … build --no-cache` of the 19 .NET services (excludes web-app/nginx so vite doesn't pollute the number). Prints wall-clock to compare against the ~33-min baseline. Does NOT start anything — pure build timing. Add `--warm` to skip `--no-cache` (measures incremental rebuild instead of cold).

Flags:
- **`--bake` is the DEFAULT** for every mode that builds. Builds route through **buildx bake** (`COMPOSE_BAKE=true`): one BuildKit graph for all targets → shared base/restore layers built once, single context scan, step-level scheduling instead of N competing SDK builds (less RAM thrash). **Measured: 33m → ~18m cold (~47% faster)**, zero file changes. Requires buildx ≥0.31 + compose ≥v5 (present).
- `--no-bake` — opt OUT of bake for this run (fall back to the classic per-service builder). Escape hatch if bake ever misbehaves.
- `--build` — rebuild the **named** service(s)/domain only (always with the parallel cap). Ignored (with a warning) if no service/domain is named — never build the whole stack.
- `--web` — also include `web-app` + `nginx` (the **production** frontend build on :3000). Off by default — for dev you run Vite via `npm start`, you don't need these.
- `--tools` — also include `pgadmin dozzle aspire-dashboard`.
- `--parallel N` — set `COMPOSE_PARALLEL_LIMIT` (default `4`).
- `--worktree` — operate on the current worktree's compose project instead of main (see Worktree section).

## Service groups (categories)

```bash
INFRA=(postgres redis rabbitmq localstack localstack-init)
TOOLS=(pgadmin dozzle aspire-dashboard)
ServiceC=(service-c-api service-c-sync-api service-c-sync-worker service-c-worker-data-erasure service-c-worker-quarantine)
ABSENCE=(service-a-api service-a-sync-api service-a-worker-data-erasure service-a-worker-deviant service-a-worker-deviant-engine service-a-worker-quarantine)
ServiceB=(service-b-api service-b-worker service-b-worker-data-erasure service-b-worker-quarantine)
MESSENGER=(service-d-api service-d-worker-quarantine service-d-worker-sms-delivery)
STATISTICS=(service-e-api)
WEB=(web-app nginx)          # production frontend — excluded unless --web
# BACKEND = everything except WEB (and TOOLS unless --tools)
BACKEND=( "${ServiceC[@]}" "${ABSENCE[@]}" "${ServiceB[@]}" "${MESSENGER[@]}" "${STATISTICS[@]}" )
```

> The APIs that workers depend on (run EF migrations): `service-c-api service-c-sync-api service-a-api service-a-sync-api service-b-api service-d-api service-e-api`. Compose `depends_on … service_healthy` already sequences these ahead of workers, so a no-`--build` `up -d` brings them up in the right order.

## Workflow

### Default / `up` — fast healthy start (no build)
```bash
cd ~/Documents/Repo
export COMPOSE_PARALLEL_LIMIT=${PARALLEL:-4}
docker compose up -d "${INFRA[@]}" ${TOOLS_IF_REQUESTED} "${BACKEND[@]}" ${WEB_IF_REQUESTED}
```
Then verify (see Verify). Note we name services explicitly so `web-app`/`nginx` are excluded deterministically.

### `recover` / `restart` — fix a broken state
```bash
cd ~/Documents/Repo
docker compose down --remove-orphans          # NEVER -v (keeps postgres/redis data)
export COMPOSE_PARALLEL_LIMIT=${PARALLEL:-4}
docker compose up -d "${INFRA[@]}" "${BACKEND[@]}"
```

### `infra`
```bash
docker compose up -d "${INFRA[@]}" ${TOOLS_IF_REQUESTED}
```

### `<domain>` (e.g. `service-a`) — optionally `--build`
```bash
export COMPOSE_PARALLEL_LIMIT=${PARALLEL:-4}
export COMPOSE_BAKE=${BAKE:-true}              # bake is default; --no-bake sets BAKE=false
docker compose up -d "${INFRA[@]}"             # ensure deps first
docker compose up -d ${BUILD_FLAG} "${ABSENCE[@]}"   # BUILD_FLAG="--build" only if --build passed
```

### `<service…>` — build only what you changed (the fast iteration loop)
```bash
export COMPOSE_PARALLEL_LIMIT=${PARALLEL:-4}
export COMPOSE_BAKE=${BAKE:-true}              # bake is default; --no-bake sets BAKE=false
docker compose up -d "${INFRA[@]}"
docker compose up -d --build service-c-api           # example: only the service you edited
```

### `down`
```bash
docker compose down               # +'--remove-orphans' if `down --hard`
```

### `bench` — time the build (cold, bake)
```bash
cd ~/Documents/Repo
SECONDS=0
NOCACHE="--no-cache"; [ "$WARM" = 1 ] && NOCACHE=""    # --warm drops --no-cache
COMPOSE_BAKE=true COMPOSE_PARALLEL_LIMIT=${PARALLEL:-4} docker compose build $NOCACHE \
  service-c-api service-c-sync-api service-c-sync-worker service-c-worker-data-erasure service-c-worker-quarantine \
  service-a-api service-a-sync-api service-a-worker-data-erasure service-a-worker-deviant service-a-worker-deviant-engine service-a-worker-quarantine \
  service-b-api service-b-worker service-b-worker-data-erasure service-b-worker-quarantine \
  service-d-api service-d-worker-quarantine service-d-worker-sms-delivery service-e-api
echo "BENCH bake$([ -z "$NOCACHE" ] && echo '+warm' || echo '+cold'): ${SECONDS}s = $((SECONDS/60))m $((SECONDS%60))s   (baseline ~33m)"
```
Report wall-clock vs the ~33-min baseline. NuGet cache-mount contents persist across `--no-cache` (only layer cache is invalidated), matching a realistic cold rebuild on an existing machine. Run with the stack down (`/docker-fast down`) for the cleanest number — a running stack competes for RAM.

> **Bake is default on all build modes** (`COMPOSE_BAKE=true`). `--no-bake` sets `BAKE=false` to fall back to the classic builder.

### Verify (run after any up/restart)
```bash
sleep 15
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
# fail signals:
docker compose ps -a --format '{{.Name}}\t{{.Status}}' | grep -iE 'exit|unhealthy|restarting' | grep -v localstack-init
# zombie check (R1):
docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}' | sort -t$'\t' -k2 -rn | head -5
```
Report: running count, any exited/unhealthy (empty = good — `localstack-init` exiting 0 is normal), and top CPU (flag anything pegged near 100%).

## Worktree / DTF use (`--worktree`)

Inside a worktree (`~/Documents/<TICKET>`), the stack runs under a per-slot compose project, **not** main. With `--worktree`:
- `cd` to the worktree dir, use its `docker-compose.worktree.*` / project name (don't touch the main stack — see the "never rebuild main" rule).
- Same modes apply; default to `infra` + only the domain(s) the ticket touches to keep RAM low.
- Pairs with `/create-stories` Step 0.6 (`docker-health-check.sh`) which *diagnoses*; this command *starts/restarts*.

## How this differs from the other docker commands (no overlap)

| Need | Command |
|---|---|
| **Start / restart** the stack fast (this) | `/docker-fast` |
| **Diagnose** zombies/unhealthy (read-only) | `~/.claude/scripts/docker-health-check.sh` (run by `/create-stories` Step 0.6) |
| Reclaim **disk** (prune images/cache) | `/docker-cleanup` |
| Tear down a **worktree** (git/tmux/vite) | `/workspace-cleanup` |

## Hard rules
- Never `up -d --build` without explicit service args. Never build the whole stack.
- Never `-v` on `down` (would wipe dev DB volumes).
- Default excludes `web-app`/`nginx` (prod frontend) — only with `--web`.
- Always export `COMPOSE_PARALLEL_LIMIT` (default 4) before any build.
- From a worktree, only act on the worktree project — never the main stack — unless run from `~/Documents/Repo`.
