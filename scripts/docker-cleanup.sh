#!/usr/bin/env bash
# docker-cleanup.sh — reclaim Docker disk space SAFELY.
#
# Why this exists: Docker bloat (build cache + dangling images + orphaned volumes)
# silently filled the host disk, which made Postgres fail CREATE TABLE with
# "PG 53100: could not extend file — No space left on device", and EF's retry
# hot-looped the service-a workers to 100% CPU. None of that touched active data —
# it was plain disk exhaustion. This script reclaims the safe-to-remove bloat so
# it doesn't happen again, WITHOUT ever touching named volumes (DB/seed data) or
# anything in use by a running container.
#
# Safe by default (no flags):
#   - stopped containers          (docker container prune)
#   - dangling images             (docker image prune)
#   - unused build cache          (docker builder prune)
#   - ORPHANED ANONYMOUS volumes  (64-hex names, referenced by no container)
#
# Flags:
#   --aggressive   also remove ALL unused images (image prune -a) and ALL build cache (builder prune -a)
#   --no-volumes   skip the orphaned-anonymous-volume sweep
#   --orphan-worktrees  also remove NAMED volumes repo-<ticket>_* whose ticket has
#                       no git worktree AND no container (dead-worktree DB/seed data).
#                       Main stack (repo_*) never matches. Honors $MEDHELP_MONOREPO.
#   --dry-run      show what WOULD be reclaimed, change nothing
#   --auto         only act if host disk usage >= threshold (for scheduled/unattended runs)
#   --threshold N  disk-usage percent that triggers --auto (default 85)
#   -h|--help
#
# NEVER removes: running containers, images in use, or any NAMED volume
# (matched defensively against a protected pattern AND restricted to 64-hex anonymous names).

set -uo pipefail

DRY=0; AGGRESSIVE=0; DO_VOLUMES=1; AUTO=0; THRESHOLD=85; ORPHAN_WT=0

# Named volumes we must never delete even if they ever showed as dangling.
PROTECT_RE='(repo|postgres|pgdata|pg_data|mssql|sqlserver|redis|rabbit|seed|_data$|data$)'

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --aggressive) AGGRESSIVE=1 ;;
    --no-volumes) DO_VOLUMES=0 ;;
    --orphan-worktrees) ORPHAN_WT=1 ;;
    --dry-run)    DRY=1 ;;
    --auto)       AUTO=1 ;;
    --threshold)  shift; THRESHOLD="${1:-85}" ;;
    -h|--help)    usage ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running — start Docker Desktop first." >&2
  exit 2
fi

# --- host disk pressure (Docker's VM disk lives on the host data volume) ---
host_disk_pct() {
  # macOS: data volume; Linux: root. Strip the trailing %.
  { df -P /System/Volumes/Data 2>/dev/null || df -P / 2>/dev/null; } \
    | awk 'NR==2 {gsub("%","",$5); print $5}'
}
PCT="$(host_disk_pct)"; PCT="${PCT:-0}"
echo "Host disk usage: ${PCT}%"

if [ "$AUTO" = 1 ] && [ "$PCT" -lt "$THRESHOLD" ]; then
  echo "--auto: ${PCT}% < ${THRESHOLD}% threshold — nothing to do."
  exit 0
fi

echo "=== Docker disk usage (before) ==="
docker system df

run() { # run a prune unless dry-run
  if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else echo "+ $*"; eval "$@"; fi
}

echo
echo "=== Pruning ==="
run "docker container prune -f"

if [ "$AGGRESSIVE" = 1 ]; then
  run "docker image prune -a -f"
  run "docker builder prune -a -f"
else
  run "docker image prune -f"
  run "docker builder prune -f"
fi

# --- orphaned ANONYMOUS volumes only (never named/DB volumes) ---
if [ "$DO_VOLUMES" = 1 ]; then
  echo
  echo "=== Orphaned anonymous volumes (64-hex, used by no container) ==="
  # dangling=true => not referenced by any container (running or stopped)
  removed=0; protected=0
  while IFS= read -r v; do
    [ -z "$v" ] && continue
    if [[ "$v" =~ ^[0-9a-f]{64}$ ]] && ! [[ "$v" =~ $PROTECT_RE ]]; then
      run "docker volume rm '$v'" && removed=$((removed+1))
    else
      echo "  protected (kept): $v"
      protected=$((protected+1))
    fi
  done < <(docker volume ls -q -f dangling=true 2>/dev/null)
  echo "Anonymous volumes removed: $removed | named/protected kept: $protected"
fi

# --- dead-worktree NAMED volumes (repo-<ticket>_*) whose worktree is gone ---
# A compose stack for a removed worktree leaves NAMED volumes (e.g.
# repo-nova-2457_postgres_data). These hold dev/seed DB data, so we remove them
# ONLY when: the ticket has no git worktree AND the volume is dangling (no container).
# The main stack (repo_*, no hyphen-ticket) never matches and is always safe.
if [ "$ORPHAN_WT" = 1 ]; then
  echo
  echo "=== Dead-worktree named volumes (no worktree + no container) ==="
  MONOREPO="${MEDHELP_MONOREPO:-$HOME/Documents/Repo}"
  ACTIVE=" "
  if [ -d "$MONOREPO/.git" ] || [ -f "$MONOREPO/.git" ]; then
    while IFS= read -r tk; do ACTIVE="$ACTIVE$tk "; done < <(
      git -C "$MONOREPO" worktree list 2>/dev/null \
        | awk '{print $NF}' | tr -d '[]' | grep -v '^main$' | tr 'A-Z' 'a-z'
    )
  else
    echo "  WARN: monorepo not found at $MONOREPO (set MEDHELP_MONOREPO) — skipping for safety."
    ORPHAN_WT=0
  fi
  if [ "$ORPHAN_WT" = 1 ]; then
    DANGLING_SET=" $(docker volume ls -q -f dangling=true 2>/dev/null | tr '\n' ' ') "
    owt_removed=0; owt_kept=0
    while IFS= read -r v; do
      [ -z "$v" ] && continue
      # parse ticket from repo-<ticket>_...  where ticket looks like nova-1234 / proj-1234
      if [[ "$v" =~ ^repo-([a-z]+-[0-9]+)_ ]]; then
        tk="${BASH_REMATCH[1]}"
        if echo "$ACTIVE" | grep -q " $tk " ; then
          owt_kept=$((owt_kept+1))                      # live worktree
        elif echo "$DANGLING_SET" | grep -q " $v " ; then
          run "docker volume rm '$v'" && owt_removed=$((owt_removed+1))   # dead + unused
        else
          echo "  in-use, kept: $v"; owt_kept=$((owt_kept+1))            # used by a container
        fi
      fi
    done < <(docker volume ls -q 2>/dev/null)
    echo "Dead-worktree volumes removed: $owt_removed | kept (live/in-use): $owt_kept"
  fi
fi

echo
echo "=== Docker disk usage (after) ==="
docker system df
echo
echo "Host disk usage now: $(host_disk_pct)% (was ${PCT}%)"
if [ "$DRY" = 1 ]; then echo "(dry-run — nothing was actually removed)"; fi

# Explicit: without this the script inherits the status of the test above, so every
# real (non-dry) run exited 1 and launchd reported the daily cleanup as failing.
exit 0
