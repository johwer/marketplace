#!/bin/bash
# cleanup-stale-projects.sh — Remove project memory dirs for worktrees that no longer exist
# Usage: bash ~/.claude/scripts/cleanup-stale-projects.sh [--dry-run]
set -eo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

MONOREPO=$(jq -r '.paths.monorepo // empty' ~/.claude/dtf-config.json 2>/dev/null)
WORKTREE_PARENT=$(jq -r '.paths.worktreeParent // empty' ~/.claude/dtf-config.json 2>/dev/null)
MONOREPO="${MONOREPO:-$HOME/Documents/Repo}"
WORKTREE_PARENT="${WORKTREE_PARENT:-$HOME/Documents}"

if [[ ! -d "$MONOREPO" ]]; then
  echo "ERROR: Monorepo not found at $MONOREPO" >&2
  exit 1
fi

ACTIVE_BRANCHES=$(cd "$MONOREPO" && git worktree list --porcelain 2>/dev/null | grep 'branch refs/heads/' | sed 's|branch refs/heads/||')
SAFE_PARENT=$(echo "$WORKTREE_PARENT" | sed 's|^/||' | sed 's|/|-|g')

COUNT=0
for dir in "$HOME/.claude/projects/-${SAFE_PARENT}-PROJ-"* "$HOME/.claude/projects/-${SAFE_PARENT}-NOVA-"*; do
  [ -d "$dir" ] || continue
  base=$(basename "$dir" | sed "s|-${SAFE_PARENT}-||" | sed 's|-apps-web$||')
  is_active=false
  while IFS= read -r branch; do
    if [ "$branch" = "$base" ]; then
      is_active=true
      break
    fi
  done <<< "$ACTIVE_BRANCHES"
  if ! $is_active; then
    if $DRY_RUN; then
      echo "Would remove: $dir"
    else
      rm -rf "$dir"
    fi
    COUNT=$((COUNT + 1))
  fi
done

if $DRY_RUN; then
  echo "Dry run: $COUNT stale dir(s) would be removed"
else
  echo "Removed $COUNT stale project memory dir(s)"
fi
