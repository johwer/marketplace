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
#   1 — one or more checks failed OR could not run (details in output; ⊘ = UNVERIFIED,
#       meaning that area was never checked — not a pass, and not a regression)

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
WARNED=0
UNVERIFIED=0
RESULTS=""

add_result() {
  local check="$1" status="$2" detail="$3"
  if [[ "$status" == "PASS" ]]; then
    RESULTS+="  ✓ $check\n"
  elif [[ "$status" == "WARN" ]]; then
    RESULTS+="  ! $check — $detail\n"
    WARNED=1
  elif [[ "$status" == "UNVERIFIED" ]]; then
    # NOT a pass. The check could not run, so it refuses rather than staying silent —
    # but it is worded differently from FAIL because the meanings are opposite:
    # UNVERIFIED = environment gap, nothing is known. FAIL = a real regression, something IS known.
    RESULTS+="  ⊘ $check — UNVERIFIED (could not run): $detail\n"
    FAILED=1
    UNVERIFIED=1
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

# ── Branch freshness ────────────────────────────
# tsc/dotnet here check the WORKING TREE. CI checks the branch MERGED WITH MAIN
# (feedback_ci_tests_merge_result). When main moves under a long-running branch, this
# script prints a green TypeScript tick and CI fails on the same commit — PROJ-3189:
# PROJ-3778 removed a member from a shared union while the branch sat in review.
# A green that does not mean what the reader thinks it means is worse than no gate, so a
# branch known to be behind FAILS. Not knowing (offline, no merge-base) warns instead of
# failing: it must not be possible to work around the FAIL by pulling the plug, but it also
# must not block a plane-mode push. A warning still says the tick below is unverified.
echo "▸ Branch freshness (vs origin/main)..."
if ! (cd "$WORKTREE" && git fetch origin main --quiet 2>&1) > /tmp/qg-fetch.log 2>&1; then
  add_result "Branch freshness" "WARN" "could not fetch origin/main (offline?) — cannot tell whether this branch is behind; the checks below are the working tree, not the merge result CI builds (see /tmp/qg-fetch.log)"
else
  MERGE_BASE=$(cd "$WORKTREE" && git merge-base HEAD origin/main 2>/dev/null || echo "")
  ORIGIN_MAIN=$(cd "$WORKTREE" && git rev-parse origin/main 2>/dev/null || echo "")
  if [[ -z "$MERGE_BASE" || -z "$ORIGIN_MAIN" ]]; then
    add_result "Branch freshness" "WARN" "could not resolve merge-base with origin/main — cannot tell whether this branch is behind"
  elif [[ "$MERGE_BASE" == "$ORIGIN_MAIN" ]]; then
    add_result "Branch freshness" "PASS" "origin/main not advanced since merge-base"
  else
    BEHIND=$(cd "$WORKTREE" && git rev-list --count "$MERGE_BASE..origin/main" 2>/dev/null || echo "?")
    (cd "$WORKTREE" && git log --oneline -10 "$MERGE_BASE..origin/main") > /tmp/qg-behind.log 2>&1 || true
    add_result "Branch freshness" "FAIL" "origin/main advanced $BEHIND commit(s) since merge-base — the checks below type-check the working tree, NOT the merge result CI builds. Rebase (git rebase origin/main) and re-run. Commits: $(tr '\n' '; ' < /tmp/qg-behind.log)"
  fi
fi
echo ""

# ── Added comments ──────────────────────────────
# CI does NOT cover this: lint, type-check and prettier all pass on a comment that
# merely restates the line below it. The rule is docs/CODING_STYLE_FRONTEND.md:256
# (PROJ-3283) and until now it was enforced only when a skill happened to tell a model
# to run the script — which means it was skipped exactly when a model chose to skip it.
#
# Runs for both areas: comment-gate filters by extension itself (.ts/.tsx/.cs/.mts/.js/.mjs),
# so there is no frontend/backend branch to make here.
#
# THREE outcomes, not two. comment-gate exits 0 both when nothing was added and when
# comments were added that it could not confidently call restating — the second prints a
# "?" list and still wants human eyes. Collapsing that into a silent PASS would hide the
# findings behind a green tick, which is the failure this script exists to prevent, so it
# warns. Its output carries ANSI colour, hence the strip before matching.
#
# A missing script FAILS rather than warns: deleting the checker must not be the way
# around a refusal.
echo "▸ Added comments (restating-comment gate)..."
COMMENT_GATE="$HOME/.claude/scripts/comment-gate.sh"
if [[ ! -x "$COMMENT_GATE" ]]; then
  add_result "Added comments" "FAIL" "comment-gate.sh not found or not executable at $COMMENT_GATE — the gate cannot run, so it refuses rather than passing silently. Restore it (/sync-config) and re-run."
else
  (cd "$WORKTREE" && bash "$COMMENT_GATE") > /tmp/qg-comments.log 2>&1
  CG_EXIT=$?
  # Strip ANSI so the file:line entries are matchable.
  sed -E 's/\x1b\[[0-9;]*m//g' /tmp/qg-comments.log > /tmp/qg-comments-plain.log
  CG_LINES=$(grep -oE '[^[:space:]]+:[0-9]+[[:space:]]+//.*' /tmp/qg-comments-plain.log 2>/dev/null | head -5 | tr '\n' ';' | sed 's/;$//' || true)
  if [[ $CG_EXIT -ne 0 ]]; then
    add_result "Added comments" "FAIL" "restating comment(s) added — each says what the line below already says. Delete them in one pass. Full list in /tmp/qg-comments.log: ${CG_LINES:-see log}"
  elif grep -q 'flagged for judgement' /tmp/qg-comments-plain.log; then
    add_result "Added comments" "WARN" "added comment(s) the gate could not auto-judge — keep only the non-obvious WHY: ${CG_LINES:-see /tmp/qg-comments.log}"
  else
    add_result "Added comments" "PASS" ""
  fi
fi
echo ""

# ── Backend checks ──────────────────────────────
if [[ "$RUN_BACKEND" == "true" ]]; then
  echo "▸ Backend checks..."

  # Find .sln files in services/
  SLN_FILES=$(find "$WORKTREE/services" -maxdepth 3 -name "*.sln" 2>/dev/null || echo "")

  # ── Toolchain precheck: "cannot build" and "build is broken" are opposite findings ──
  # PROJ-3279: a resumed branch had a hard C# compile error AND a global.json SDK pin the host
  # could not satisfy. Both exited through the same ".NET build FAILED" line, which reads as an
  # environment nit — so the real regression was dismissed. Separate them BEFORE building:
  # UNVERIFIED still fails the gate (nothing is known, so it must not pass), but it says the
  # backend was never checked instead of claiming a regression that may not exist.
  DOTNET_OK=true
  DOTNET_WHY=""
  if ! command -v dotnet >/dev/null 2>&1; then
    DOTNET_OK=false
    DOTNET_WHY="no dotnet on PATH"
  elif ! (cd "$WORKTREE" && dotnet --version) > /tmp/qg-sdk.log 2>&1; then
    # `dotnet --version` resolves global.json from the CWD, so a pin the host cannot satisfy
    # fails right here — before any compilation, and with the SDK's own explanation.
    DOTNET_OK=false
    PINNED=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$WORKTREE/global.json" 2>/dev/null | head -1 | grep -oE '[0-9][^"]*' || echo "see global.json")
    DOTNET_WHY="global.json pins SDK $PINNED; host has $(dotnet --list-sdks 2>/dev/null | tr '\n' ' ' | cut -c1-120 || echo 'none'). rollForward cannot go backwards. $(head -2 /tmp/qg-sdk.log | tr '\n' ' ')"
  fi

  if [[ "$DOTNET_OK" == "false" ]]; then
    add_result ".NET toolchain" "UNVERIFIED" "$DOTNET_WHY — the backend was NOT checked. This is not a regression and not a pass: nothing is known about the C# in this branch. CI is the only gate; say 'backend unverified' rather than 'build failed'."
  fi

  if [[ "$DOTNET_OK" == "true" && -n "$SLN_FILES" ]]; then
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
  elif [[ "$DOTNET_OK" == "true" ]]; then
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
    # PROJ-3438: removing a devDependency dropped a hoisted transitive `lodash` that app
    # code had imported undeclared for months. Prettier, ESLint, tsc and Vitest all passed;
    # only `npm run build` caught it. A static substitute does not work — the broken import
    # was two hops down the transitive chain from the package actually removed.
    if echo "$CHANGED" | grep -qE '^apps/web/package(-lock)?\.json$'; then
      echo "  → Production build (dependencies changed)..."
      if (cd "$WEB_DIR" && npm run build 2>&1) > /tmp/qg-build.log 2>&1; then
        add_result "Production build" "PASS" "$(grep -oE 'built in [0-9.]+m?s' /tmp/qg-build.log 2>/dev/null | tail -1 || true)"
      else
        BUILD_ERRORS=$(grep -iE 'failed to resolve|error during build|Error:' /tmp/qg-build.log 2>/dev/null | head -5 || true)
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
# clients (PROJ-3438). Triggered independently of the web section — a branch can touch
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
if [[ "$FAILED" -eq 0 && "$WARNED" -eq 0 ]]; then
  echo " ✓ All quality gates passed"
elif [[ "$FAILED" -eq 0 ]]; then
  echo " ✓ Quality gates passed, with warnings"
elif [[ "$UNVERIFIED" -eq 1 ]]; then
  echo " ⊘ Some checks could NOT RUN — do not report this as a pass or as a regression."
  echo "   An UNVERIFIED line means that area is unchecked, not that it is broken."
  echo "   Read the ⊘ lines below and say which area is unverified when you report."
else
  echo " ✗ Some checks failed — fix before pushing"
fi
echo "───────────────────────────────────────────"
echo -e "$RESULTS"

exit $FAILED
