#!/bin/bash
# Resume a Claude workspace in tmux — picks up where a previous Dream Team left off
# Usage: resume-workspace.sh <TICKET_ID>

TICKET_ID="$1"

if [ -z "$TICKET_ID" ]; then
  echo "Usage: resume-workspace.sh <TICKET_ID>"
  exit 1
fi

# Load config for worktree parent path (falls back to ~/Documents)
source "$(dirname "$0")/dtf-env.sh" 2>/dev/null || true
WORKTREE_PARENT="${DTF_WORKTREE_PARENT:-$HOME/Documents}"
MONOREPO="${DTF_MONOREPO:-$HOME/Documents/Repo}"

WORKTREE="$WORKTREE_PARENT/$TICKET_ID"

if [ ! -d "$WORKTREE" ]; then
  echo "Error: Worktree not found at $WORKTREE"
  exit 1
fi

cd "$WORKTREE" || exit 1
unset CLAUDECODE

# Kill existing tmux session if any (stale from previous day)
tmux kill-session -t "$TICKET_ID" 2>/dev/null

# Gather context for the resume prompt
PR_INFO=$(cd "$MONOREPO" && gh pr list --head "$TICKET_ID" --json number,title,state,url --jq '.[0] // empty' 2>/dev/null)
GIT_STATUS=$(git status --short 2>/dev/null)
GIT_LOG=$(git log --oneline -5 2>/dev/null)
NOTES_EXISTS=""
if [ -d ".dream-team/notes" ]; then
  NOTES_EXISTS="yes"
fi

# Build resume prompt
RESUME_PROMPT="/my-dream-team --resume $TICKET_ID"

# Start tmux detached in the worktree directory, send claude, wait, send resume command, then attach
tmux new-session -d -s "$TICKET_ID" -c "$WORKTREE"
tmux send-keys -t "$TICKET_ID" "claude --dangerously-skip-permissions --chrome" Enter

echo "Waiting for Claude to start..."
sleep 8

tmux send-keys -t "$TICKET_ID" "$RESUME_PROMPT" Enter

tmux attach -t "$TICKET_ID"
