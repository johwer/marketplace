#!/bin/bash
# poll-ci-checks.sh — Poll GitHub PR for CI check results
#
# Usage: bash ~/.claude/scripts/poll-ci-checks.sh <OWNER/REPO> <PR_NUMBER> [MAX_MINUTES] [INTERVAL_SECONDS]
#
# Polls a GitHub PR's status checks (GitHub Actions) until all complete or timeout.
# Early exit: stops as soon as any check fails (no point waiting for the rest).
# Exits with 0 when all checks pass, 1 on failure/timeout, 2 on error.

set -euo pipefail

OWNER_REPO="${1:?Usage: poll-ci-checks.sh <OWNER/REPO> <PR_NUMBER> [MAX_MINUTES] [INTERVAL_SECONDS]}"
PR_NUMBER="${2:?Usage: poll-ci-checks.sh <OWNER/REPO> <PR_NUMBER> [MAX_MINUTES] [INTERVAL_SECONDS]}"
MAX_MINUTES="${3:-10}"
INTERVAL="${4:-30}"

MAX_SECONDS=$((MAX_MINUTES * 60))
ELAPSED=0
START_TIME=$(date +%s)
LOG_FILE="$HOME/.claude/logs/ci-check-times.csv"

# Ensure log dir and header exist
mkdir -p "$(dirname "$LOG_FILE")"
if [ ! -f "$LOG_FILE" ]; then
  echo "date,repo,pr,elapsed_seconds,result,passed,failed,pending" > "$LOG_FILE"
fi

# Get the HEAD SHA for this PR
HEAD_SHA=$(gh api "repos/${OWNER_REPO}/pulls/${PR_NUMBER}" --jq '.head.sha' 2>/dev/null || echo "")
if [ -z "$HEAD_SHA" ]; then
  echo "Error: Could not get HEAD SHA for PR #${PR_NUMBER}"
  exit 2
fi

echo "Polling CI checks for PR #${PR_NUMBER} on ${OWNER_REPO}..."
echo "HEAD SHA: ${HEAD_SHA:0:8}"
echo "Max wait: ${MAX_MINUTES} minutes, checking every ${INTERVAL} seconds"
echo ""

while [ "$ELAPSED" -lt "$MAX_SECONDS" ]; do
  # Get all check runs for this commit
  CHECKS=$(gh api "repos/${OWNER_REPO}/commits/${HEAD_SHA}/check-runs" 2>/dev/null || echo '{"check_runs":[]}')

  TOTAL=$(echo "$CHECKS" | jq '.total_count // 0')
  COMPLETED=$(echo "$CHECKS" | jq '[.check_runs[] | select(.status == "completed")] | length')
  PASSED=$(echo "$CHECKS" | jq '[.check_runs[] | select(.conclusion == "success")] | length')
  FAILED=$(echo "$CHECKS" | jq '[.check_runs[] | select(.conclusion == "failure")] | length')
  PENDING=$((TOTAL - COMPLETED))

  if [ "$TOTAL" -eq 0 ]; then
    MINS=$((ELAPSED / 60))
    echo "  No checks found yet... (${MINS}m elapsed)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
    continue
  fi

  # Early exit: if any check already failed, stop immediately — no point waiting for the rest
  if [ "$FAILED" -gt 0 ]; then
    ACTUAL=$(($(date +%s) - START_TIME))

    echo "=== CI Check Results (early exit — failure detected after ${ACTUAL}s) ==="
    echo ""
    echo "$CHECKS" | jq -r '.check_runs[] | select(.status == "completed") | "  \(if .conclusion == "success" then "PASS" elif .conclusion == "failure" then "FAIL" elif .conclusion == "skipped" then "SKIP" else .conclusion end) — \(.name)"'
    if [ "$PENDING" -gt 0 ]; then
      echo "$CHECKS" | jq -r '.check_runs[] | select(.status != "completed") | "  PENDING — \(.name)"'
    fi
    echo ""
    echo "=== Failed Checks ==="
    echo "$CHECKS" | jq -r '.check_runs[] | select(.conclusion == "failure") | "FAIL: \(.name)\n  URL: \(.html_url)\n"'
    echo ""
    echo "Stopped polling early: ${FAILED} check(s) failed, ${PENDING} still pending."

    # Log timing
    echo "$(date +%Y-%m-%d_%H:%M),${OWNER_REPO},${PR_NUMBER},${ACTUAL},fail,${PASSED},${FAILED},${PENDING}" >> "$LOG_FILE"
    exit 1
  fi

  # All checks completed and none failed
  if [ "$PENDING" -eq 0 ]; then
    ACTUAL=$(($(date +%s) - START_TIME))

    echo "=== CI Check Results (${ACTUAL}s) ==="
    echo ""
    echo "$CHECKS" | jq -r '.check_runs[] | "  \(if .conclusion == "success" then "PASS" elif .conclusion == "skipped" then "SKIP" else .conclusion end) — \(.name)"'
    echo ""
    echo "All CI checks passed. (${PASSED} passed, ${TOTAL} total)"

    # Log timing
    echo "$(date +%Y-%m-%d_%H:%M),${OWNER_REPO},${PR_NUMBER},${ACTUAL},pass,${PASSED},0,0" >> "$LOG_FILE"
    exit 0
  fi

  # Show progress with per-check status
  MINS=$((ELAPSED / 60))
  echo "  ${COMPLETED}/${TOTAL} done (${PASSED} passed, ${PENDING} pending)... (${MINS}m elapsed)"
  echo "$CHECKS" | jq -r '.check_runs[] | select(.status == "completed" and .conclusion == "success") | "    PASS — \(.name)"'
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

# Log timeout
ACTUAL=$(($(date +%s) - START_TIME))
echo "$(date +%Y-%m-%d_%H:%M),${OWNER_REPO},${PR_NUMBER},${ACTUAL},timeout,${PASSED:-0},${FAILED:-0},${PENDING:-0}" >> "$LOG_FILE"

echo ""
echo "Timeout: CI checks not completed after ${MAX_MINUTES} minutes."
echo "Check GitHub Actions manually."
exit 1
