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

WORKTREE="$WORKTREE_PARENT/$TICKET_ID"
cd "$WORKTREE" || exit 1
unset CLAUDECODE

# Start tmux detached, send claude, wait, send dream team command, then attach
tmux new-session -d -s "$TICKET_ID" -c "$WORKTREE"
tmux send-keys -t "$TICKET_ID" "cd \"$WORKTREE\"" Enter
# Select the project's pinned Node (apps/web/.nvmrc) before starting Claude, so the
# session and anything Claude spawns match the repo's version — not the nvm default.
tmux send-keys -t "$TICKET_ID" 'source "${NVM_DIR:-$HOME/.nvm}/nvm.sh" >/dev/null 2>&1; [ -f apps/web/.nvmrc ] && nvm use "$(cat apps/web/.nvmrc)" >/dev/null 2>&1' Enter
tmux send-keys -t "$TICKET_ID" "claude --permission-mode auto" Enter

echo "Waiting for Claude to start..."
sleep 8

submit_prompt() {
  local session="$1" text="$2" buf="dtf-prompt-$1" tries
  tmux set-buffer -b "$buf" -- "$text"
  tmux paste-buffer -p -b "$buf" -d -t "$session"
  for tries in 1 2 3; do
    sleep 2
    tmux send-keys -t "$session" C-m
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 1
      if tmux capture-pane -p -t "$session" | grep -q '⏺'; then
        echo "Prompt submitted in $session."
        return 0
      fi
    done
  done
  echo "WARNING: no ⏺ in $session after 3 Enter attempts: the prompt may still sit unsent. Check with: tmux attach -t $session" >&2
  return 1
}

if [ -n "$DREAM_TEAM_PROMPT" ]; then
  submit_prompt "$TICKET_ID" "$DREAM_TEAM_PROMPT"
fi

tmux attach -t "$TICKET_ID"
