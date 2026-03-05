#!/usr/bin/env bash
# auto-lint-notify.sh — PostToolUse hook that reminds to lint after editing source files
# Runs async so it doesn't block. Outputs a reminder, not the actual lint.
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

case "$TOOL_NAME" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // ""')

case "$FILE_PATH" in
  *.cs)
    echo "💅 Edited .cs file — remember to run 'dotnet csharpier .' before committing."
    ;;
  *.ts|*.tsx)
    # Only remind, don't auto-run (could be slow in large projects)
    echo "💅 Edited .ts/.tsx file — remember to run ESLint before committing."
    ;;
esac
