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
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""')

if [ "$EVENT" = "PreToolUse" ]; then
  BASE=$(basename "$FILE_PATH")
  if [ "$TOOL_NAME" = "Write" ] && [ ! -e "$FILE_PATH" ] \
    && echo "$FILE_PATH" | grep -qE '/Migrations/[0-9]{14}_[^/]+\.cs$' \
    && ! echo "$BASE" | grep -qE '\.Designer\.cs$' \
    && [ ! -e "${FILE_PATH%.cs}.Designer.cs" ]; then
    echo "MIGRATION GUARD — blocked: $BASE has no sibling .Designer.cs, so EF never registers it and Database.Migrate() silently skips it." >&2
    echo "Generate it with 'dotnet ef migrations add <Name> --project <svc>.API --startup-project <svc>.API' (pinned SDK image), which writes the .cs, the .Designer.cs and the snapshot together. Rebase onto origin/main first, then read Up() for anything outside your change." >&2
    exit 2
  fi
  exit 0
fi

if echo "$FILE_PATH" | grep -iqE '/(migrations|Migration)/'; then
  echo "⚠️  MIGRATION GUARD: You edited a migration file."
  echo "   File: $FILE_PATH"
  echo "   Migration files should only be created via 'dotnet ef migrations add', not hand-edited."
  echo "   If this is intentional, proceed with caution."
fi
