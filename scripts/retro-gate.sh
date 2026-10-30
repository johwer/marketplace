#!/bin/bash
# TeammateIdle hook — prevents the team lead from going idle without running a retro.
#
# Only fires for the team lead (amara) in Dream Team sessions.
# Checks that dream-team-learnings have been appended for this ticket.
#
# Exit 0 = allow idle
# Exit 2 = prevent idle, stderr fed back as feedback

set -euo pipefail

INPUT=$(cat)
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // empty')
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // empty')

# Only gate the team lead
if [ -z "$TEAMMATE_NAME" ] || [ "$TEAMMATE_NAME" != "amara" ]; then
  exit 0
fi

# Extract ticket ID
TICKET_ID=$(echo "$TEAM_NAME" | sed 's/^dream-team-//')
if [ -z "$TICKET_ID" ]; then
  exit 0
fi

# Find worktree
WORKTREE="$HOME/Documents/$TICKET_ID"
if [ ! -d "$WORKTREE" ]; then
  exit 0
fi

# Check 1: Retro section exists in dream-team-learnings.md
LEARNINGS_FILE="$HOME/.claude/projects/$(printf '%s' "$HOME" | sed 's#[/.]#-#g')-Documents-Repo/memory/dream-team-learnings.md"
if [ -f "$LEARNINGS_FILE" ]; then
  if grep -q "$TICKET_ID" "$LEARNINGS_FILE" 2>/dev/null; then
    # Retro was written — allow idle
    exit 0
  fi
fi

# Check 2: Local retro file exists in .dream-team/
RETRO_FILE="$WORKTREE/.dream-team/retro.md"
if [ -f "$RETRO_FILE" ] && [ -s "$RETRO_FILE" ]; then
  exit 0
fi

# No retro found — block
echo "RETRO GATE: You haven't run the retrospective (Phase 6.75) yet.
Run the retro before going idle. Write learnings to .dream-team/retro.md OR append to dream-team-learnings.md with the $TICKET_ID header.
This is a hard gate — don't skip it." >&2
exit 2
