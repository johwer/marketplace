#!/bin/bash
# TeammateIdle hook — prevents dev agents from going idle if quality gates aren't met.
#
# Receives JSON on stdin: { "teammate_name": "...", "team_name": "..." }
# Exit 0 = allow idle (normal)
# Exit 2 = prevent idle, stderr fed back as feedback to the agent
#
# This hook checks whether the agent has:
# 1. Written their notes file (.dream-team/notes/<name>.md)
# 2. Written at least one journal entry (.dream-team/journal/<name>.md)
# 3. Run formatting on changed files (checked via git status for unstaged changes)
#
# Only applies to dev agents (kenji, ingrid, ravi, elsa, mei, diego).
# Non-dev agents (amara, maya, suki, lena, tane) are always allowed to go idle.

set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // empty')
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // empty')

# If we can't parse input, allow idle (don't block on hook errors)
if [ -z "$TEAMMATE_NAME" ]; then
  exit 0
fi

# Only gate dev agents — let coordinators/reviewers/testers idle freely
case "$TEAMMATE_NAME" in
  kenji|ingrid|ravi|elsa|mei|diego) ;;
  *) exit 0 ;;
esac

# Extract ticket ID from team name (dream-team-PROJ-1234 -> PROJ-1234)
TICKET_ID=$(echo "$TEAM_NAME" | sed 's/^dream-team-//')
if [ -z "$TICKET_ID" ]; then
  exit 0
fi

# Find the worktree path
WORKTREE="$HOME/Documents/$TICKET_ID"
if [ ! -d "$WORKTREE" ]; then
  # Not in a worktree setup — allow idle
  exit 0
fi

ERRORS=""

# Check 1: Notes file exists and has content
NOTES_FILE="$WORKTREE/.dream-team/notes/${TEAMMATE_NAME}.md"
if [ ! -f "$NOTES_FILE" ] || [ ! -s "$NOTES_FILE" ]; then
  ERRORS="${ERRORS}You haven't created your notes file at .dream-team/notes/${TEAMMATE_NAME}.md yet. Create it with the required sections (Decisions, Files Touched, Assumptions, For Next Phase) before going idle.\n"
fi

# Check 2: Journal file exists and has at least one entry
JOURNAL_FILE="$WORKTREE/.dream-team/journal/${TEAMMATE_NAME}.md"
if [ ! -f "$JOURNAL_FILE" ] || [ ! -s "$JOURNAL_FILE" ]; then
  ERRORS="${ERRORS}You haven't written any journal entries at .dream-team/journal/${TEAMMATE_NAME}.md. Write at least one entry (instruction-gap, convention-gap, positive, etc.) before going idle.\n"
fi

# Check 3: No unstaged formatting changes (indicates formatting wasn't run)
cd "$WORKTREE" 2>/dev/null || exit 0
DIRTY_CS=$(git diff --name-only -- '*.cs' 2>/dev/null | wc -l | tr -d ' ')
DIRTY_TS=$(git diff --name-only -- '*.ts' '*.tsx' 2>/dev/null | wc -l | tr -d ' ')

if [ "$DIRTY_CS" -gt 0 ] && [[ "$TEAMMATE_NAME" =~ ^(kenji|ravi|mei|diego)$ ]]; then
  ERRORS="${ERRORS}You have $DIRTY_CS unstaged .cs file(s). Run 'dotnet csharpier .' and stage/commit your changes before going idle.\n"
fi

if [ "$DIRTY_TS" -gt 0 ] && [[ "$TEAMMATE_NAME" =~ ^(ingrid|elsa)$ ]]; then
  ERRORS="${ERRORS}You have $DIRTY_TS unstaged .ts/.tsx file(s). Run 'npx prettier --write . && npx eslint --fix .' and stage/commit before going idle.\n"
fi

# If any errors, prevent idle
if [ -n "$ERRORS" ]; then
  echo -e "QUALITY GATE: You can't go idle yet.\n${ERRORS}Complete these items first, then you can go idle." >&2
  exit 2
fi

# All checks pass — allow idle
exit 0
