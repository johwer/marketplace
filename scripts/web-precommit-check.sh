#!/bin/bash
# Pre-commit quality gate for apps/web — runs Prettier check, ESLint, and tsc
# Called from PreToolUse hook on Bash when command contains "git commit"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Only run on git commit commands
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Find the repo root (look for apps/web relative to CWD or common parent dirs)
find_web_dir() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/apps/web/src" ]; then
      echo "$dir/apps/web"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

WEB_DIR=$(find_web_dir)
if [ -z "$WEB_DIR" ]; then
  exit 0  # Not in a repo with apps/web, skip
fi

# Staged web files under src, relative to apps/web. Prettier and ESLint run on these
# only: checking all of src blocks every commit on files the commit never touched,
# such as an ignored .playwright-cli/ snapshot dir under src (PROJ-4647).
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
STAGED=()
while IFS= read -r f; do
  [ -n "$f" ] && [ -e "$REPO_ROOT/$f" ] && STAGED+=("${f#apps/web/}")
done < <(git diff --cached --name-only --diff-filter=d -- "apps/web/src/" 2>/dev/null)
if [ ${#STAGED[@]} -eq 0 ]; then
  exit 0  # No web files staged, skip
fi

LINTABLE=()
for f in "${STAGED[@]}"; do
  case "$f" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) LINTABLE+=("$f") ;;
  esac
done

cd "$WEB_DIR" || exit 0

ERRORS=""

# Prettier check (staged files only; [warn] lines go to stderr, so capture both)
PRETTIER_OUT=$(npx prettier --check --ignore-unknown --no-editorconfig "${STAGED[@]}" 2>&1)
if [ $? -ne 0 ]; then
  BAD_FILES=$(echo "$PRETTIER_OUT" | grep "^\[warn\]" | grep -v "Code style issues" | head -5)
  ERRORS="${ERRORS}Prettier: files need formatting\n${BAD_FILES:-$(echo "$PRETTIER_OUT" | tail -3)}\n\n"
fi

# ESLint (errors only, not warnings; staged lintable files only)
if [ ${#LINTABLE[@]} -gt 0 ]; then
  ESLINT_OUT=$(npx eslint --quiet "${LINTABLE[@]}" 2>/dev/null)
  if [ $? -ne 0 ] && [ -n "$ESLINT_OUT" ]; then
    ERRORS="${ERRORS}ESLint errors:\n$(echo "$ESLINT_OUT" | head -10)\n\n"
  fi
fi

# TypeScript
TSC_OUT=$(npx tsc --noEmit 2>&1)
if [ $? -ne 0 ]; then
  ERRORS="${ERRORS}TypeScript errors:\n$(echo "$TSC_OUT" | grep "error TS" | head -10)\n\n"
fi

if [ -n "$ERRORS" ]; then
  echo "{\"decision\":\"block\",\"reason\":\"Pre-commit web checks failed:\\n${ERRORS}Fix these before committing.\"}"
  exit 0
fi

exit 0
