#!/bin/bash
# Launch a Claude workspace in tmux — runs self-contained in a new terminal window
# Usage: launch-workspace.sh <TICKET_ID> <DREAM_TEAM_PROMPT>

TICKET_ID="$1"
DREAM_TEAM_PROMPT="$2"

if [ -z "$TICKET_ID" ]; then
  echo "Usage: launch-workspace.sh <TICKET_ID> <DREAM_TEAM_PROMPT>"
  exit 1
fi

# Load config for worktree parent path (falls back to ~/Documents)
source "$(dirname "$0")/dtf-env.sh" 2>/dev/null || true
WORKTREE_PARENT="${DTF_WORKTREE_PARENT:-$HOME/Documents}"

cd "$WORKTREE_PARENT/$TICKET_ID" || exit 1
unset CLAUDECODE

# Start tmux detached, send claude, wait, send dream team command, then attach
tmux new-session -d -s "$TICKET_ID"
# Select the project's pinned Node (apps/web/.nvmrc) before starting Claude, so the
# session and anything Claude spawns match the repo's version — not the nvm default.
tmux send-keys -t "$TICKET_ID" 'source "${NVM_DIR:-$HOME/.nvm}/nvm.sh" >/dev/null 2>&1; [ -f apps/web/.nvmrc ] && nvm use "$(cat apps/web/.nvmrc)" >/dev/null 2>&1' Enter
tmux send-keys -t "$TICKET_ID" "claude --dangerously-skip-permissions" Enter

echo "Waiting for Claude to start..."
sleep 8

if [ -n "$DREAM_TEAM_PROMPT" ]; then
  tmux send-keys -t "$TICKET_ID" "$DREAM_TEAM_PROMPT" Enter
fi

tmux attach -t "$TICKET_ID"
