#!/usr/bin/env bash
# backend-skill-reminder.sh — PostToolUse (Edit|Write) hook.
# The first time a session edits C# under services/ or shared/, it reminds Claude which
# backend skills apply. No backend skill loads on its own, so without this the checklist
# and the tech leads' standing decisions are only used when someone remembers them.
# Once per session, never on frontend edits, so it costs nothing on the other half of the repo.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // ""')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

case "$FILE_PATH" in
  */services/*.cs|*/shared/*.cs|*/services/*.csproj|*/shared/*.csproj) ;;
  *) exit 0 ;;
esac

MARKER_DIR="${TMPDIR:-/tmp}/claude-backend-reminder"
mkdir -p "$MARKER_DIR"
MARKER="$MARKER_DIR/$SESSION_ID"
[[ -e "$MARKER" ]] && exit 0
touch "$MARKER"

MSG="Backend C# edited. Before calling it done: check it against the standing decisions in /ghost-review (current tech lead) and /owl-review, and run the dotnet-backend-review checklist on the diff (EF Core, transactions, async, config, logging, jobs). Team decisions are in backend-decisions. Naming a skill does not load it: invoke it, or read its SKILL.md."

jq -n --arg msg "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
