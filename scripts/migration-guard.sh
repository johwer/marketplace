#!/usr/bin/env bash
# migration-guard.sh — PostToolUse hook that warns when editing migration files
# Fires on Edit/Write tools, checks if the path contains migrations/
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

# Only check Edit and Write
case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // ""')

if echo "$FILE_PATH" | grep -iqE '/(migrations|Migration)/'; then
  echo "⚠️  MIGRATION GUARD: You edited a migration file."
  echo "   File: $FILE_PATH"
  echo "   Migration files should only be created via 'dotnet ef migrations add', not hand-edited."
  echo "   If this is intentional, proceed with caution."
fi
