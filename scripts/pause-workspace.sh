#!/bin/bash
# Pause a workspace — kill the tmux session but keep worktree and all files
# Usage: pause-workspace.sh <TICKET_ID>

TICKET_ID="$1"

if [ -z "$TICKET_ID" ]; then
  echo "Usage: pause-workspace.sh <TICKET_ID>"
  echo ""
  echo "Active tmux sessions:"
  tmux list-sessions 2>/dev/null || echo "  (none)"
  exit 1
fi

echo "=== Pausing workspace: $TICKET_ID ==="

# Kill any running Vite/Node dev servers in this worktree
# Load config for worktree parent path (falls back to ~/Documents)
source "$(dirname "$0")/dtf-env.sh" 2>/dev/null || true
WORKTREE_PARENT="${DTF_WORKTREE_PARENT:-$HOME/Documents}"

WORKTREE="$WORKTREE_PARENT/$TICKET_ID"
if [ -d "$WORKTREE" ]; then
  # Find node processes whose cwd is inside this worktree
  PIDS=$(pgrep -f "node.*$WORKTREE" 2>/dev/null || true)
  if [ -z "$PIDS" ]; then
    # Fallback: check lsof for listening node processes in this worktree
    PIDS=$(lsof -i -P 2>/dev/null | grep node | grep LISTEN | grep "$WORKTREE" | awk '{print $2}' | sort -u || true)
  fi
  if [ -n "$PIDS" ]; then
    echo "Stopping dev server(s): $PIDS"
    echo "$PIDS" | xargs kill 2>/dev/null || true
  fi
fi

# Kill the tmux session
if tmux has-session -t "$TICKET_ID" 2>/dev/null; then
  tmux kill-session -t "$TICKET_ID"
  echo "✓ tmux session '$TICKET_ID' killed"
else
  echo "No tmux session '$TICKET_ID' found (already stopped)"
fi

echo ""
echo "Preserved:"
echo "  Worktree: ~/Documents/$TICKET_ID"
echo "  Notes:    ~/Documents/$TICKET_ID/.dream-team/"
echo "  Git:      all commits and branches intact"
echo ""
echo "To resume tomorrow: tell the orchestrator 'resume $TICKET_ID'"
