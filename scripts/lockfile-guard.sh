#!/usr/bin/env bash
# lockfile-guard.sh — PostToolUse hook that warns when editing lock files
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // ""')
BASENAME=$(basename "$FILE_PATH")

case "$BASENAME" in
  package-lock.json|pnpm-lock.yaml|yarn.lock)
    echo "⚠️  LOCK FILE GUARD: You modified a lock file."
    echo "   File: $FILE_PATH"
    echo "   Lock files should be updated via package manager (npm i, pnpm i), not edited directly."
    echo "   If this was unintentional, revert with: git checkout -- $FILE_PATH"
    ;;
esac
