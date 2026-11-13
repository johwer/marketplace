#!/bin/bash
# cleanup-workspace.sh — Tear down a DTF worktree: worktree services, containers, images and volumes,
# dev servers, tmux session, worktree directory and git refs. Shared by /workspace-cleanup and
# /create-stories; the PR-state and review-thread checks stay with the caller (they need the user).
#
# Usage: bash ~/.claude/scripts/cleanup-workspace.sh <TICKET_ID> [--delete-branch] [--discard-local-work] [--dry-run]
#   --delete-branch       also `git branch -D <TICKET_ID>` (ask the user first)
#   --discard-local-work  proceed although the worktree has uncommitted or unpushed work (ask the user first)
#   --dry-run             print what would be removed, change nothing
#
# Exit: 0 done, 1 usage, 3 refused (uncommitted work, or commits not pushed to an existing upstream;
#       nothing was touched). A branch with no upstream is the caller's "no PR" check.

set -uo pipefail

usage() { sed -n 2,12p "$0" | sed 's/^# \{0,1\}//'; }

TICKET_ID=""
DELETE_BRANCH=0
DISCARD=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --delete-branch) DELETE_BRANCH=1 ;;
    --discard-local-work) DISCARD=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown flag: $arg" >&2; usage >&2; exit 1 ;;
    *) TICKET_ID="$arg" ;;
  esac
done
[ -n "$TICKET_ID" ] || { usage >&2; exit 1; }

source "$(dirname "$0")/dtf-env.sh" 2>/dev/null || true
WORKTREE_PARENT="${DTF_WORKTREE_PARENT:-$HOME/Documents}"
MONOREPO="${DTF_MONOREPO:-}"
[ -d "$MONOREPO/.git" ] || MONOREPO="$HOME/Documents/Repo"
WORKTREE="$WORKTREE_PARENT/$TICKET_ID"
TICKET_LOWER=$(printf '%s' "$TICKET_ID" | tr '[:upper:]' '[:lower:]')
TICKET_PATTERN="(^|[^0-9a-z])${TICKET_LOWER}([^0-9]|$)"

run() {
  if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi
}

ticket_names() { grep -E -- "$TICKET_PATTERN" || true; }

kill_port_if_owned() {
  local port="$1" pid cwd
  [ -n "$port" ] || return 0
  for pid in $(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null); do
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    case "$cwd" in
      "$WORKTREE"|"$WORKTREE"/*) echo "Port $port: stopping PID $pid (cwd $cwd)"; run kill "$pid" ;;
      *) echo "Port $port: PID $pid belongs to ${cwd:-unknown cwd}, left running" ;;
    esac
  done
}

cd "$MONOREPO" || { echo "Monorepo not found at $MONOREPO" >&2; exit 1; }
echo "=== Cleaning up $TICKET_ID (worktree $WORKTREE) ==="

if [ -d "$WORKTREE/.git" ] || [ -f "$WORKTREE/.git" ]; then
  DIRTY=$(git -C "$WORKTREE" status --porcelain 2>/dev/null)
  UNPUSHED=0
  if git -C "$WORKTREE" rev-parse --verify --quiet '@{u}' >/dev/null; then
    UNPUSHED=$(git -C "$WORKTREE" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  fi
  if [ -n "$DIRTY" ] || [ "${UNPUSHED:-0}" -gt 0 ]; then
    [ -n "$DIRTY" ] && { echo "Uncommitted changes:"; echo "$DIRTY" | head -20; }
    [ "${UNPUSHED:-0}" -gt 0 ] && echo "Commits not pushed to the upstream branch: $UNPUSHED"
    if [ "$DISCARD" = 0 ]; then
      echo "REFUSED: local work would be lost. Rerun with --discard-local-work once the user confirms."
      exit 3
    fi
    echo "Discarding local work (--discard-local-work)."
  fi
fi

if [ -d "$WORKTREE" ]; then
  run bash "$HOME/.claude/skills/bridge-pre/bin/archive-live.sh" "$TICKET_ID" "$WORKTREE" || echo "bridge archive failed (continuing)"
  run bash "$HOME/.claude/scripts/worktree-service.sh" --worktree "$WORKTREE" down || echo "worktree-service down failed; containers are removed by name below"
  ENV_LOCAL="$WORKTREE/apps/web/.env.local"
  for var in VITE_DEV_PORT COSMOS_UI_PORT COSMOS_RENDERER_PORT; do
    kill_port_if_owned "$(grep -E "^${var}=" "$ENV_LOCAL" 2>/dev/null | tail -1 | cut -d= -f2)"
  done
fi

run bash "$HOME/.claude/scripts/pause-workspace.sh" "$TICKET_ID" || true
tmux has-session -t "$TICKET_ID" 2>/dev/null && run tmux kill-session -t "$TICKET_ID"

CONTAINERS=$(docker ps -a --format '{{.Names}}' 2>/dev/null | ticket_names)
IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | ticket_names)
VOLUMES=$(docker volume ls -q 2>/dev/null | grep -E -- "^repo-${TICKET_LOWER}_" || true)
echo "Containers: ${CONTAINERS:-none}" | tr '\n' ' '; echo
echo "Images:     ${IMAGES:-none}" | tr '\n' ' '; echo
echo "Volumes:    ${VOLUMES:-none}" | tr '\n' ' '; echo
[ -n "$CONTAINERS" ] && run docker rm -f $CONTAINERS >/dev/null
[ -n "$IMAGES" ] && run docker rmi $IMAGES >/dev/null
[ -n "$VOLUMES" ] && run docker volume rm $VOLUMES >/dev/null

if git worktree list --porcelain | grep -qx "worktree $WORKTREE"; then
  run git worktree remove "$WORKTREE" --force
fi
[ -e "$WORKTREE" ] && run rm -rf "$WORKTREE"
run git worktree prune
run rm -f "$HOME/.claude/workspace-status/$TICKET_ID.json"

if [ "$DELETE_BRANCH" = 1 ] && git show-ref --verify --quiet "refs/heads/$TICKET_ID"; then
  run git branch -D "$TICKET_ID"
fi

echo ""
git worktree list
