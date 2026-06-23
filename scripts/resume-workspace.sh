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

# === Validate worktree environment ===
ENV_WARNINGS=""

# Check .env exists with port allocations
if [ ! -f ".env" ]; then
  ENV_WARNINGS="${ENV_WARNINGS}\n⚠️  .env missing — regenerating ports..."
  bash "$(dirname "$0")/allocate-ports.sh" "$TICKET_ID" 2>/dev/null
  if [ ! -f ".env" ]; then
    ENV_WARNINGS="${ENV_WARNINGS}\n❌ Port allocation failed. Run manually: bash ~/.claude/scripts/allocate-ports.sh $TICKET_ID"
  fi
elif ! grep -qE "^(ServiceB|ServiceC|ABSENCE|STATISTICS|MESSENGER)_API_PORT=" .env 2>/dev/null; then
  ENV_WARNINGS="${ENV_WARNINGS}\n⚠️  .env exists but missing API port vars — regenerating..."
  bash "$(dirname "$0")/allocate-ports.sh" "$TICKET_ID" 2>/dev/null
fi

# Check apps/web/.env.local exists
if [ ! -f "apps/web/.env.local" ]; then
  ENV_WARNINGS="${ENV_WARNINGS}\n⚠️  apps/web/.env.local missing — Vite dev server may use wrong port"
fi

# Check for stale Docker containers on worktree ports
if [ -f ".env" ]; then
  STALE_PORTS=""
  while IFS='=' read -r key val; do
    if [[ "$key" == *_API_PORT ]] && [ -n "$val" ]; then
      PID=$(lsof -ti :"$val" 2>/dev/null)
      if [ -n "$PID" ]; then
        STALE_PORTS="${STALE_PORTS}\n  Port $val ($key) in use by PID $PID"
      fi
    fi
  done < <(grep "_API_PORT=" .env 2>/dev/null)
  if [ -n "$STALE_PORTS" ]; then
    ENV_WARNINGS="${ENV_WARNINGS}\n⚠️  Ports already in use (stale containers?):${STALE_PORTS}"
  fi
fi

if [ -n "$ENV_WARNINGS" ]; then
  echo -e "\n=== Worktree Environment Check ===${ENV_WARNINGS}\n"
fi

# Ensure worktree CLAUDE.md exists (prevents DTF amnesia in spawned sessions)
if [ ! -f "$WORKTREE/CLAUDE.md" ] || ! grep -q "DTF Worktree" "$WORKTREE/CLAUDE.md" 2>/dev/null; then
  bash "$(dirname "$0")/write-worktree-claude-md.sh" "$TICKET_ID" 2>/dev/null || true
fi

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
# Select the project's pinned Node (apps/web/.nvmrc) before starting Claude, so the
# session and anything Claude spawns match the repo's version — not the nvm default.
tmux send-keys -t "$TICKET_ID" 'source "${NVM_DIR:-$HOME/.nvm}/nvm.sh" >/dev/null 2>&1; [ -f apps/web/.nvmrc ] && nvm use "$(cat apps/web/.nvmrc)" >/dev/null 2>&1' Enter
tmux send-keys -t "$TICKET_ID" "claude --dangerously-skip-permissions --chrome" Enter

echo "Waiting for Claude to start..."
sleep 8

tmux send-keys -t "$TICKET_ID" "$RESUME_PROMPT" Enter

tmux attach -t "$TICKET_ID"
