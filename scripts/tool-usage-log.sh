#!/usr/bin/env bash
# tool-usage-log.sh — Logs all tool usage to a CSV for building allowlists
# Used as a PostToolUse hook in settings.json
# Each line: timestamp,session_id,tool_name,tool_input_summary
#
# To analyze: sort ~/.claude/logs/tool-usage.csv | uniq -c | sort -rn
# To extract Bash commands: grep ',Bash,' ~/.claude/logs/tool-usage.csv | cut -d',' -f4-

set -euo pipefail

LOG_FILE="$HOME/.claude/logs/tool-usage.csv"

# Read JSON payload from stdin
INPUT=$(cat)

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')

# Extract a short summary depending on tool type
case "$TOOL_NAME" in
  Bash)
    SUMMARY=$(echo "$INPUT" | jq -r '.tool_input.command // ""' | head -1 | cut -c1-200)
    ;;
  Read)
    SUMMARY=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
    ;;
  Write|Edit)
    SUMMARY=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
    ;;
  Glob)
    SUMMARY=$(echo "$INPUT" | jq -r '.tool_input.pattern // ""')
    ;;
  Grep)
    SUMMARY=$(echo "$INPUT" | jq -r '.tool_input.pattern // ""')
    ;;
  Task)
    SUMMARY=$(echo "$INPUT" | jq -r '.tool_input.description // ""')
    ;;
  *)
    SUMMARY=$(echo "$INPUT" | jq -r '.tool_input | keys | join("+")' 2>/dev/null || echo "")
    ;;
esac

# Escape commas in summary for CSV
SUMMARY=$(echo "$SUMMARY" | tr ',' ';' | tr '\n' ' ' | cut -c1-200)

# Write header if file doesn't exist
if [ ! -f "$LOG_FILE" ]; then
  echo "timestamp,session_id,tool_name,summary" > "$LOG_FILE"
fi

echo "${TIMESTAMP},${SESSION_ID},${TOOL_NAME},${SUMMARY}" >> "$LOG_FILE"
