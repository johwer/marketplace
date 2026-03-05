#!/bin/bash
# TaskCompleted hook — prevents dev agents from marking tasks complete if quality gates aren't met.
#
# Receives JSON on stdin: { "task_id": "...", "task_subject": "...", "task_description": "...",
#                           "teammate_name": "...", "team_name": "..." }
# Exit 0 = allow task completion
# Exit 2 = prevent completion, stderr fed back as feedback to the agent
#
# Checks (for dev agents):
# 1. Notes file exists with content
# 2. Journal file exists with at least one entry
# 3. "For Next Phase" section has been filled in (not empty)
# 4. git diff --name-only shows the agent actually touched files (not an empty completion)
# 5. No compilation errors (tsc/dotnet build)
#
# Non-dev agents (amara, maya, suki, lena, tane) get lighter checks.

set -euo pipefail

# Read JSON from stdin
INPUT=$(cat)
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // empty')
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // empty')
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty')

# If we can't parse input, allow completion
if [ -z "$TEAMMATE_NAME" ]; then
  exit 0
fi

# Extract ticket ID from team name
TICKET_ID=$(echo "$TEAM_NAME" | sed 's/^dream-team-//')
if [ -z "$TICKET_ID" ]; then
  exit 0
fi

# Find the worktree path
WORKTREE="$HOME/Documents/$TICKET_ID"
if [ ! -d "$WORKTREE" ]; then
  exit 0
fi

# Skip lightweight tasks (analysis, summary, review — not implementation)
# Only enforce hard gates on implementation tasks
case "$TASK_SUBJECT" in
  *[Aa]nalyze*|*[Ss]ummary*|*[Rr]eview*|*[Rr]etro*|*[Vv]erif*|*[Rr]ecord*|*[Tt]est*)
    # Lighter check: only notes file required for non-implementation tasks
    NOTES_FILE="$WORKTREE/.dream-team/notes/${TEAMMATE_NAME}.md"
    if [ ! -f "$NOTES_FILE" ] || [ ! -s "$NOTES_FILE" ]; then
      echo "TASK GATE: Create your notes file at .dream-team/notes/${TEAMMATE_NAME}.md before marking this task complete." >&2
      exit 2
    fi
    exit 0
    ;;
esac

# Non-dev agents get lighter checks
case "$TEAMMATE_NAME" in
  amara|maya|suki|lena|tane)
    NOTES_FILE="$WORKTREE/.dream-team/notes/${TEAMMATE_NAME}.md"
    if [ ! -f "$NOTES_FILE" ] || [ ! -s "$NOTES_FILE" ]; then
      echo "TASK GATE: Create your notes file at .dream-team/notes/${TEAMMATE_NAME}.md before marking this task complete." >&2
      exit 2
    fi
    exit 0
    ;;
esac

# === Dev agent gates (kenji, ingrid, ravi, elsa, mei, diego) ===
ERRORS=""

# Gate 1: Notes file
NOTES_FILE="$WORKTREE/.dream-team/notes/${TEAMMATE_NAME}.md"
if [ ! -f "$NOTES_FILE" ] || [ ! -s "$NOTES_FILE" ]; then
  ERRORS="${ERRORS}Missing notes file: .dream-team/notes/${TEAMMATE_NAME}.md — create it with Decisions, Files Touched, Assumptions, For Next Phase sections.\n"
fi

# Gate 2: Journal file with entries
JOURNAL_FILE="$WORKTREE/.dream-team/journal/${TEAMMATE_NAME}.md"
if [ ! -f "$JOURNAL_FILE" ] || [ ! -s "$JOURNAL_FILE" ]; then
  ERRORS="${ERRORS}Missing journal entries: .dream-team/journal/${TEAMMATE_NAME}.md — write at least one entry before completing.\n"
fi

# Gate 3: "For Next Phase" section has content (not just the header)
if [ -f "$NOTES_FILE" ]; then
  # Extract content after "## For Next Phase" header
  NEXT_PHASE_CONTENT=$(sed -n '/^## For Next Phase/,/^## /p' "$NOTES_FILE" | tail -n +2 | grep -v '^$' | grep -v '^## ' | head -5)
  if [ -z "$NEXT_PHASE_CONTENT" ]; then
    ERRORS="${ERRORS}The '## For Next Phase' section in your notes is empty. Fill it with a 5-line summary: what you built, key decisions, deviations, risks, and what the next agent needs to know.\n"
  fi
fi

# Gate 4: Agent actually made code changes
cd "$WORKTREE" 2>/dev/null || exit 0
CHANGED_FILES=$(git diff --name-only origin/main 2>/dev/null | wc -l | tr -d ' ')
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
TOTAL_CHANGES=$((CHANGED_FILES + STAGED_FILES))

if [ "$TOTAL_CHANGES" -eq 0 ]; then
  ERRORS="${ERRORS}No code changes detected (git diff --name-only origin/main is empty). Did you forget to save/commit your work?\n"
fi

# Gate 5: Type check (lightweight — only check if there are relevant files)
case "$TEAMMATE_NAME" in
  kenji|ravi|mei|diego)
    # Check for .cs compilation errors only if there are C# changes
    CS_CHANGES=$(git diff --name-only origin/main -- '*.cs' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$CS_CHANGES" -gt 0 ]; then
      # Find which service was changed
      SERVICE_DIR=$(git diff --name-only origin/main -- 'services/' 2>/dev/null | head -1 | cut -d'/' -f1-3)
      if [ -n "$SERVICE_DIR" ]; then
        SLN_FILE=$(find "$WORKTREE/$SERVICE_DIR" -name "*.sln" -maxdepth 2 2>/dev/null | head -1)
        if [ -n "$SLN_FILE" ]; then
          BUILD_OUTPUT=$(cd "$WORKTREE" && dotnet build "$SLN_FILE" 2>&1 | tail -3)
          if echo "$BUILD_OUTPUT" | grep -q "Build FAILED"; then
            ERRORS="${ERRORS}Build failed. Fix compilation errors before completing:\n$(echo "$BUILD_OUTPUT" | head -5)\n"
          fi
        fi
      fi
    fi
    ;;
  ingrid|elsa)
    # Check TypeScript compilation
    TS_CHANGES=$(git diff --name-only origin/main -- '*.ts' '*.tsx' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$TS_CHANGES" -gt 0 ] && [ -d "$WORKTREE/apps/web" ]; then
      TSC_OUTPUT=$(cd "$WORKTREE/apps/web" && npx tsc --noEmit 2>&1 | tail -5)
      TSC_EXIT=$?
      if [ $TSC_EXIT -ne 0 ]; then
        ERRORS="${ERRORS}TypeScript errors found. Fix them before completing:\n$(echo "$TSC_OUTPUT" | head -5)\n"
      fi
    fi
    ;;
esac

# If any errors, prevent completion
if [ -n "$ERRORS" ]; then
  echo -e "TASK COMPLETION BLOCKED:\n${ERRORS}Fix these issues before marking the task as complete." >&2
  exit 2
fi

# All gates pass
exit 0
