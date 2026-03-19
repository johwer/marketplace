#!/bin/bash
# e2e-show-all.sh — Run e2e-show in parallel across multiple worktrees.
#
# Opens one terminal window per worktree, each running headed Playwright
# with failing tests auto-skipped.
#
# Usage:
#   bash ~/.claude/scripts/e2e-show-all.sh                    # all worktrees
#   bash ~/.claude/scripts/e2e-show-all.sh PROJ-2238 PROJ-2229  # specific ones
#   bash ~/.claude/scripts/e2e-show-all.sh --ui               # Playwright UI mode
#
# Reads monorepo path from ~/.claude/dtf-config.json.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DTF_CONFIG="$HOME/.claude/dtf-config.json"
E2E_SCRIPT="$HOME/.claude/scripts/e2e-show.mjs"

# ── Read config ───────────────────────────────────────────────────────────

TERMINAL=$(node -e "try{const c=JSON.parse(require('fs').readFileSync('$DTF_CONFIG','utf-8'));process.stdout.write(c.terminal||'Alacritty')}catch{process.stdout.write('Alacritty')}" 2>/dev/null)
MONOREPO=$(node -e "try{const c=JSON.parse(require('fs').readFileSync('$DTF_CONFIG','utf-8'));process.stdout.write(c.monorepoPath||'')}catch{}" 2>/dev/null)

if [ -z "$MONOREPO" ]; then
  echo "❌ monorepoPath not set in $DTF_CONFIG"
  exit 1
fi

# ── Parse args ────────────────────────────────────────────────────────────

MODE="--headed"
SPECIFIC_WORKTREES=()

for arg in "$@"; do
  if [[ "$arg" == --* ]]; then
    MODE="$arg"
  else
    SPECIFIC_WORKTREES+=("$arg")
  fi
done

# ── Resolve worktree directories ──────────────────────────────────────────

declare -a WORKTREE_DIRS=()

if [ ${#SPECIFIC_WORKTREES[@]} -gt 0 ]; then
  # Specific ticket IDs given — look them up as sibling dirs or git worktrees
  WORKTREE_PARENT=$(dirname "$MONOREPO")
  for ticket in "${SPECIFIC_WORKTREES[@]}"; do
    candidate="$WORKTREE_PARENT/$ticket"
    if [ -d "$candidate" ]; then
      WORKTREE_DIRS+=("$candidate")
    else
      echo "⚠️  Worktree not found: $candidate"
    fi
  done
else
  # Auto-detect all worktrees via git, exclude the main worktree
  while IFS= read -r line; do
    dir="${line#worktree }"
    if [ "$dir" != "$MONOREPO" ]; then
      WORKTREE_DIRS+=("$dir")
    fi
  done < <(git -C "$MONOREPO" worktree list --porcelain | grep "^worktree ")
fi

if [ ${#WORKTREE_DIRS[@]} -eq 0 ]; then
  echo "No worktrees found. Pass ticket IDs or create worktrees first."
  echo "Usage: bash ~/.claude/scripts/e2e-show-all.sh PROJ-2238 PROJ-2229"
  exit 1
fi

# ── Open one terminal per worktree ────────────────────────────────────────

echo "Opening ${#WORKTREE_DIRS[@]} terminal(s) in $MODE mode..."
echo ""

for worktree in "${WORKTREE_DIRS[@]}"; do
  ticket=$(basename "$worktree")

  # Read port from .env.local for display
  port=""
  env_local="$worktree/apps/web/.env.local"
  if [ -f "$env_local" ]; then
    port=$(grep -m1 "^VITE_DEV_PORT=" "$env_local" 2>/dev/null | cut -d= -f2 || true)
  fi
  port_label=${port:+" (port $port)"}

  echo "▶  $ticket$port_label"

  CMD="cd \"$worktree\" && echo '' && echo '═══ $ticket$port_label ═══' && echo '' && node \"$E2E_SCRIPT\" $MODE; echo ''; echo 'Done — press Enter to close'; read"

  bash "$SCRIPT_DIR/open-terminal.sh" "$TERMINAL" "$CMD"

  # Small stagger so windows don't stack exactly on top of each other
  sleep 0.4
done

echo ""
echo "✅ ${#WORKTREE_DIRS[@]} terminal(s) launched"
