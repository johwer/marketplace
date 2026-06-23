# Docker Cleanup — Global Housekeeping

Reclaim Docker disk space **without** touching resources belonging to active worktrees or running Repo services. Complements `/workspace-cleanup`, which handles per-worktree Docker. This command handles everything else.

## What this does vs. what `/workspace-cleanup` does

| Scope | Command |
|---|---|
| Per-worktree containers/images (`repo-<ticket>-*-wt`) | `/workspace-cleanup <TICKET_ID>` |
| Global: stopped containers, dangling images, build cache, (optional) volumes | **this command** |

Running `/workspace-cleanup` on every worktree does NOT reclaim build cache or dangling images — those live in the global pool.

## Input

$ARGUMENTS

**Implementation:** this command runs the deterministic script `~/.claude/scripts/docker-cleanup.sh` (zero LLM tokens). Prefer the script over ad-hoc `docker prune` commands.

```bash
bash ~/.claude/scripts/docker-cleanup.sh [flags]
```

Flags (passed straight to the script):
- (default, no flags) — stopped containers + dangling images + unused build cache + **orphaned ANONYMOUS volumes** (64-hex, used by no container). All safe; never touches named volumes or in-use resources.
- `--aggressive` — also remove ALL unused images (`image prune -a`) and ALL build cache (`builder prune -a`).
- `--no-volumes` — skip the orphaned-anonymous-volume sweep.
- `--dry-run` — show what would be reclaimed, change nothing.
- `--auto [--threshold N]` — only act if host disk usage ≥ N% (default 85). For scheduled/unattended prevention runs.

**Why volumes are now safe by default:** the script removes ONLY anonymous orphaned volumes (64-hex names referenced by no container) and defensively protects any named volume (Postgres/Redis/RabbitMQ/seed DB data). The old blanket `docker volume prune` risk — deleting a stopped stack's DB volume — is gone, so no `--volumes` flag is needed.

## Safety model

1. **Never pass `--volumes` without the user explicitly requesting it.** Dev DB data is persistent and hard to recreate.
2. **Active worktree protection** — enumerate `git worktree list` in `~/Documents/Repo`. For each ticket worktree, its `repo-<ticket-lowercase>-*-wt` images/containers belong to that worktree. If the worktree's compose stack is **up**, those images are automatically protected by `docker image prune` (they're in use). If it's **down**, they'd be eligible for `-a` pruning — **warn the user** before aggressive mode.
3. **Running Repo services are always safe** — `docker image prune` (with or without `-a`) never removes images in use by running containers.
4. **Never stop running containers.** This command only removes already-stopped containers.

## Workflow

### Step 1: Show current state

```bash
docker system df
echo "---"
cd ~/Documents/Repo && git worktree list
echo "---"
docker ps --format 'table {{.Names}}\t{{.Status}}' | head -30
```

### Step 2: Identify at-risk worktree images (aggressive mode only)

If `--aggressive` was passed, list images that belong to worktrees whose compose stack is currently **down** — these would be removed:

```bash
# Get active ticket IDs from worktrees
ACTIVE_TICKETS=$(cd ~/Documents/Repo && git worktree list | awk '{print $3}' | tr -d '[]' | grep -v '^main$' | tr '[:upper:]' '[:lower:]')

# Show worktree images that are NOT in use (would be pruned by -a)
for t in $ACTIVE_TICKETS; do
  IN_USE=$(docker ps --format '{{.Image}}' | grep -c "repo-$t-" || true)
  IMAGES=$(docker images --format '{{.Repository}}' | grep "^repo-$t-" | wc -l | tr -d ' ')
  if [ "$IMAGES" -gt 0 ] && [ "$IN_USE" -eq 0 ]; then
    echo "WARNING: worktree $t has $IMAGES images but stack is DOWN — aggressive prune will remove them (rebuild on next /workspace-launch)"
  fi
done
```

If any warnings printed, ask the user to confirm before proceeding. Images can always be rebuilt, but rebuilds can take several minutes per worktree.

### Step 3: Run the cleanup script

```bash
bash ~/.claude/scripts/docker-cleanup.sh [--aggressive] [--no-volumes] [--dry-run]
```

The script prints before/after `docker system df` and the host-disk delta itself — no need to wrap it. For `--aggressive` with a worktree whose stack is **down**, surface the Step 2 warning and confirm first.

### Step 4: Report reclaimed space

The script's after/before `docker system df` output is the report. Summarize the delta to the user, e.g., "Reclaimed 6.3 GB (images 5.1 GB, anonymous volumes 1.2 GB); host disk 85% → 81%."

## Preventing recurrence (don't have this again)

Disk exhaustion (build cache + dangling images + orphaned volumes) once filled the host disk and made Postgres fail `CREATE TABLE` with `PG 53100: No space left on device`, hot-looping the service-a workers to 100% CPU. To keep ahead of it, run the safe sweep on a schedule:

```bash
# only acts when host disk >= 85%; safe to run unattended
bash ~/.claude/scripts/docker-cleanup.sh --auto
```

Wire this via `/schedule` (e.g. daily) or call `--auto` from `docker-health-check.sh`. The default sweep never touches named/DB volumes.

## Important rules

- **Default is conservative.** Only remove unused images / full build cache when the user passes `--aggressive`.
- **Never prune volumes by default.** Requires explicit `--volumes` flag AND user confirmation after showing what would be removed.
- **Never stop running containers.** If the user wants to reclaim space from a running worktree, direct them to `/workspace-cleanup`.
- **Always show the active worktree list first** so the user sees what's at risk before destructive action.
- If `--aggressive` is combined with any worktree whose stack is down, warn explicitly and require confirmation.
