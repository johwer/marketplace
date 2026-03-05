#!/usr/bin/env bash
# quality-gate.sh — Deterministic pre-push quality checks
# Runs formatting, type checks, and build verification.
# Called by the Dream Team team lead before git push — saves Opus tokens
# by running mechanical checks as a script instead of inline LLM commands.
#
# Usage: bash quality-gate.sh <worktree-path> [--backend] [--frontend] [--all]
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed (details in output)

set -euo pipefail

WORKTREE="${1:?Usage: quality-gate.sh <worktree-path> [--backend] [--frontend] [--all]}"
shift

# Parse flags
RUN_BACKEND=false
RUN_FRONTEND=false

for arg in "$@"; do
  case "$arg" in
    --backend)  RUN_BACKEND=true ;;
    --frontend) RUN_FRONTEND=true ;;
    --all)      RUN_BACKEND=true; RUN_FRONTEND=true ;;
    *)          echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# If no flags, auto-detect from changed files
if [[ "$RUN_BACKEND" == "false" && "$RUN_FRONTEND" == "false" ]]; then
  CHANGED=$(cd "$WORKTREE" && git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "")
  if echo "$CHANGED" | grep -q '\.cs$'; then
    RUN_BACKEND=true
  fi
  if echo "$CHANGED" | grep -qE '\.(tsx?|jsx?)$'; then
    RUN_FRONTEND=true
  fi
  # If still nothing detected, run both
  if [[ "$RUN_BACKEND" == "false" && "$RUN_FRONTEND" == "false" ]]; then
    RUN_BACKEND=true
    RUN_FRONTEND=true
  fi
fi

FAILED=0
RESULTS=""

add_result() {
  local check="$1" status="$2" detail="$3"
  if [[ "$status" == "PASS" ]]; then
    RESULTS+="  ✓ $check\n"
  else
    RESULTS+="  ✗ $check — $detail\n"
    FAILED=1
  fi
}

echo "═══════════════════════════════════════════"
echo " Quality Gate — Pre-Push Checks"
echo " Worktree: $WORKTREE"
echo "═══════════════════════════════════════════"
echo ""

# ── Backend checks ──────────────────────────────
if [[ "$RUN_BACKEND" == "true" ]]; then
  echo "▸ Backend checks..."

  # Find .sln files in services/
  SLN_FILES=$(find "$WORKTREE/services" -maxdepth 3 -name "*.sln" 2>/dev/null || echo "")

  if [[ -n "$SLN_FILES" ]]; then
    # CSharpier formatting
    echo "  → CSharpier format check..."
    if (cd "$WORKTREE" && dotnet csharpier --check . 2>&1) > /tmp/qg-csharpier.log 2>&1; then
      add_result "CSharpier formatting" "PASS" ""
    else
      # Auto-fix formatting
      (cd "$WORKTREE" && dotnet csharpier . 2>&1) > /dev/null 2>&1 || true
      add_result "CSharpier formatting" "PASS" "(auto-fixed)"
    fi

    # .NET build
    echo "  → .NET build..."
    BUILD_OUTPUT=""
    BUILD_PASS=true
    while IFS= read -r sln; do
      if ! (cd "$WORKTREE" && dotnet build "$sln" --no-restore 2>&1) > /tmp/qg-build.log 2>&1; then
        BUILD_PASS=false
        BUILD_OUTPUT=$(tail -5 /tmp/qg-build.log)
      fi
    done <<< "$SLN_FILES"

    if [[ "$BUILD_PASS" == "true" ]]; then
      add_result ".NET build" "PASS" ""
    else
      add_result ".NET build" "FAIL" "$BUILD_OUTPUT"
    fi
  else
    add_result "Backend (no .sln found)" "PASS" "skipped"
  fi
fi

# ── Frontend checks ─────────────────────────────
if [[ "$RUN_FRONTEND" == "true" ]]; then
  echo "▸ Frontend checks..."

  WEB_DIR="$WORKTREE/apps/web"
  if [[ -d "$WEB_DIR" ]]; then
    # Load nvm if available
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" 2>/dev/null

    # Prettier formatting
    echo "  → Prettier format..."
    if (cd "$WEB_DIR" && npx prettier --write . 2>&1) > /tmp/qg-prettier.log 2>&1; then
      add_result "Prettier formatting" "PASS" ""
    else
      add_result "Prettier formatting" "FAIL" "$(tail -3 /tmp/qg-prettier.log)"
    fi

    # ESLint
    echo "  → ESLint..."
    if (cd "$WEB_DIR" && npx eslint --fix . 2>&1) > /tmp/qg-eslint.log 2>&1; then
      add_result "ESLint" "PASS" ""
    else
      ESLINT_ERRORS=$(grep -c "error" /tmp/qg-eslint.log 2>/dev/null || echo "?")
      add_result "ESLint" "FAIL" "$ESLINT_ERRORS errors (see /tmp/qg-eslint.log)"
    fi

    # TypeScript type check
    echo "  → TypeScript type check..."
    if (cd "$WEB_DIR" && npx tsc --noEmit 2>&1) > /tmp/qg-tsc.log 2>&1; then
      add_result "TypeScript (tsc --noEmit)" "PASS" ""
    else
      TSC_ERRORS=$(tail -3 /tmp/qg-tsc.log)
      add_result "TypeScript (tsc --noEmit)" "FAIL" "$TSC_ERRORS"
    fi
  else
    add_result "Frontend (no apps/web found)" "PASS" "skipped"
  fi
fi

# ── Summary ─────────────────────────────────────
echo ""
echo "───────────────────────────────────────────"
if [[ "$FAILED" -eq 0 ]]; then
  echo " ✓ All quality gates passed"
else
  echo " ✗ Some checks failed — fix before pushing"
fi
echo "───────────────────────────────────────────"
echo -e "$RESULTS"

exit $FAILED
