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

Flags:
- `--aggressive` — also remove unused images (`docker image prune -a`) and all build cache (`builder prune -a`). Default is conservative (dangling only).
- `--volumes` — also prune unused volumes. **Off by default** because dev databases (Postgres, Redis data) can live in volumes. Only pass this if you're sure.
- `--dry-run` — show what would be reclaimed, change nothing.

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

### Step 3: Prune

**Conservative (default):**

```bash
docker container prune -f
docker image prune -f        # dangling only (untagged)
docker builder prune -f      # dangling cache only
```

**Aggressive (`--aggressive`):**

```bash
docker container prune -f
docker image prune -a -f     # unused images too
docker builder prune -a -f   # all build cache
```

**Volumes (`--volumes`, only if explicitly requested):**

```bash
# Show first, confirm, then prune
docker volume ls --filter dangling=true
docker volume prune -f
```

**Dry run (`--dry-run`):**

Skip the actual prune commands. Instead, show what each would reclaim:

```bash
docker system df -v | head -60
docker container ls -a --filter status=exited --filter status=created
docker images --filter dangling=true
```

### Step 4: Report reclaimed space

```bash
docker system df
```

Compare to the Step 1 baseline and report: e.g., "Reclaimed 27.3 GB (images: 10.2 GB, build cache: 20.5 GB, containers: trivial)."

## Important rules

- **Default is conservative.** Only remove unused images / full build cache when the user passes `--aggressive`.
- **Never prune volumes by default.** Requires explicit `--volumes` flag AND user confirmation after showing what would be removed.
- **Never stop running containers.** If the user wants to reclaim space from a running worktree, direct them to `/workspace-cleanup`.
- **Always show the active worktree list first** so the user sees what's at risk before destructive action.
- If `--aggressive` is combined with any worktree whose stack is down, warn explicitly and require confirmation.
