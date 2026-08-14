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

# Compute the set of files THIS branch changed, once, for both auto-detect and the
# prettier/eslint file scoping below. Imprecise detection is the root cause of two
# bugs: (1) `git diff HEAD` alone misses committed changes, so a fully-committed
# frontend-only branch falls back to "run both" and spuriously runs backend checks;
# (2) formatting/linting the whole tree reformats files never clean on main.
#
# Changed set = committed-since-main (origin/main...HEAD) ∪ working-tree (vs HEAD)
# ∪ untracked, excluding deletions. Paths are relative to the worktree root.
BASE_REF=""
if (cd "$WORKTREE" && git rev-parse --verify --quiet origin/main >/dev/null 2>&1); then
  BASE_REF="origin/main"
fi
collect_changed() {
  cd "$WORKTREE" || return
  if [[ -n "$BASE_REF" ]]; then
    git diff --name-only --diff-filter=d "$BASE_REF"...HEAD 2>/dev/null
  fi
  git diff --name-only --diff-filter=d HEAD 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null
}
CHANGED=$(collect_changed | sort -u)

# If no flags, auto-detect from changed files. Detect by AREA (path), not just
# extension — a frontend-only branch that touches config/docs (e.g. eslint.config.mjs,
# *.md) has no .tsx/.jsx file but is still frontend-only and must not trigger backend.
if [[ "$RUN_BACKEND" == "false" && "$RUN_FRONTEND" == "false" ]]; then
  if echo "$CHANGED" | grep -qE '\.cs$|^services/|^shared/'; then
    RUN_BACKEND=true
  fi
  if echo "$CHANGED" | grep -q '^apps/web/'; then
    RUN_FRONTEND=true
  fi
  # If still nothing detected (no recognizable area changed), run both.
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

    # Scope prettier/eslint to THIS branch's changed files only (CHANGED, computed
    # above) — never the whole tree. Running `prettier --write .` / `eslint --fix .`
    # reformats files that were never clean on main and lints paths CI never touches
    # (e.g. scripts/*.mjs outside src), producing collateral diffs the dev then has to
    # revert. We mirror the "stage by explicit path" policy: only touch what changed.
    #
    # Web files relative to apps/web (for the cd "$WEB_DIR" context below).
    # bash 3.2-compatible (no mapfile): read newline-separated paths into arrays.
    PRETTIER_TARGETS=()
    ESLINT_TARGETS=()
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      # Prettier: any changed web file (--ignore-unknown skips unsupported types).
      PRETTIER_TARGETS+=("$f")
      # ESLint: changed web files under src/ with a lintable extension — matches
      # CI's `eslint src` scope and avoids erroring on non-JS/TS paths.
      if [[ "$f" == src/* && "$f" =~ \.(tsx?|jsx?|mjs|cjs)$ ]]; then
        ESLINT_TARGETS+=("$f")
      fi
    done < <(echo "$CHANGED" | grep '^apps/web/' | sed 's#^apps/web/##')

    # Prettier formatting (changed files only)
    echo "  → Prettier format..."
    if [[ ${#PRETTIER_TARGETS[@]} -eq 0 ]]; then
      echo "skipped — no changed web files" > /tmp/qg-prettier.log
      add_result "Prettier formatting" "PASS" "no changed web files"
    elif (cd "$WEB_DIR" && npx prettier --write --ignore-unknown "${PRETTIER_TARGETS[@]}" 2>&1) > /tmp/qg-prettier.log 2>&1; then
      add_result "Prettier formatting" "PASS" "${#PRETTIER_TARGETS[@]} changed file(s)"
    else
      add_result "Prettier formatting" "FAIL" "$(tail -3 /tmp/qg-prettier.log)"
    fi

    # ESLint (eslint_d if available for ~10x faster warm runs, fallback to eslint)
    echo "  → ESLint..."
    if command -v eslint_d &>/dev/null; then
      ESLINT_CMD="eslint_d"
    else
      ESLINT_CMD="npx eslint"
    fi
    if [[ ${#ESLINT_TARGETS[@]} -eq 0 ]]; then
      echo "skipped — no changed src files" > /tmp/qg-eslint.log
      add_result "ESLint" "PASS" "no changed src files"
    elif (cd "$WEB_DIR" && $ESLINT_CMD --fix "${ESLINT_TARGETS[@]}" 2>&1) > /tmp/qg-eslint.log 2>&1; then
      add_result "ESLint" "PASS" "$ESLINT_CMD, ${#ESLINT_TARGETS[@]} changed file(s)"
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

    # Vitest — only tests related to changed files
    echo "  → Vitest (changed files only)..."
    if (cd "$WEB_DIR" && npx vitest run --changed 2>&1) > /tmp/qg-vitest.log 2>&1; then
      TEST_COUNT=$(grep -oE '[0-9]+ passed' /tmp/qg-vitest.log | tail -1 || echo "passed")
      add_result "Vitest (--changed)" "PASS" "$TEST_COUNT"
    else
      VITEST_ERRORS=$(tail -5 /tmp/qg-vitest.log)
      add_result "Vitest (--changed)" "FAIL" "$VITEST_ERRORS"
    fi

    # Production build — REQUIRED when dependencies change, because tsc cannot catch it.
    # tsc resolves the TYPE graph; the bundler resolves the MODULE graph. They agree only
    # while every runtime import has a matching, correctly-scoped package. Declare
    # @types/x without x itself and tsc goes green on a build that cannot bundle.
    # NOVA-3438: removing a devDependency dropped a hoisted transitive `lodash` that app
    # code had imported undeclared for months. Prettier, ESLint, tsc and Vitest all passed;
    # only `npm run build` caught it. A static substitute does not work — the broken import
    # was two hops down the transitive chain from the package actually removed.
    if echo "$CHANGED" | grep -qE '^apps/web/package(-lock)?\.json$'; then
      echo "  → Production build (dependencies changed)..."
      if (cd "$WEB_DIR" && npm run build 2>&1) > /tmp/qg-build.log 2>&1; then
        add_result "Production build" "PASS" "$(grep -oE 'built in [0-9.]+m?s' /tmp/qg-build.log | tail -1)"
      else
        BUILD_ERRORS=$(grep -iE 'failed to resolve|error during build|Error:' /tmp/qg-build.log | head -5)
        [[ -z "$BUILD_ERRORS" ]] && BUILD_ERRORS=$(tail -5 /tmp/qg-build.log)
        add_result "Production build" "FAIL" "$BUILD_ERRORS"
      fi
    fi
  else
    add_result "Frontend (no apps/web found)" "PASS" "skipped"
  fi
fi

# ── Mobile (apps/mobile) ─────────────────────────
# The gate had NO mobile coverage at all: a branch touching apps/mobile passed with zero
# checks run against it. That matters more now that web and mobile share generated API
# clients (NOVA-3438). Triggered independently of the web section — a branch can touch
# either, or both.
# Note there is no cheap bundler check here: mobile builds via EAS (cloud) or expo run:*
# (needs a simulator), so the dependency-change build gate above has no mobile equivalent.
MOBILE_DIR="$WORKTREE/apps/mobile"
if echo "$CHANGED" | grep -qE '^apps/mobile/' && [[ -d "$MOBILE_DIR" ]]; then
  echo ""
  echo "▸ Mobile checks..."

  echo "  → Prettier format..."
  if (cd "$MOBILE_DIR" && npx prettier --check . --no-editorconfig 2>&1) > /tmp/qg-m-prettier.log 2>&1; then
    add_result "Mobile Prettier" "PASS" ""
  else
    add_result "Mobile Prettier" "FAIL" "$(tail -5 /tmp/qg-m-prettier.log)"
  fi

  echo "  → ESLint..."
  if (cd "$MOBILE_DIR" && npm run lint 2>&1) > /tmp/qg-m-lint.log 2>&1; then
    add_result "Mobile ESLint" "PASS" ""
  else
    add_result "Mobile ESLint" "FAIL" "$(grep -E 'error|✖' /tmp/qg-m-lint.log | head -5)"
  fi

  echo "  → TypeScript type check..."
  if (cd "$MOBILE_DIR" && npm run type-check 2>&1) > /tmp/qg-m-tsc.log 2>&1; then
    add_result "Mobile TypeScript" "PASS" ""
  else
    add_result "Mobile TypeScript" "FAIL" "$(grep -E 'error TS' /tmp/qg-m-tsc.log | head -5)"
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
