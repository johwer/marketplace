#!/bin/bash
# poll-ai-reviews.sh — Poll GitHub PR for AI bot review comments
#
# Usage: bash ~/.claude/scripts/poll-ai-reviews.sh <OWNER/REPO> <PR_NUMBER> [MAX_MINUTES] [INTERVAL_SECONDS]
#
# Polls a GitHub PR for AI bot review comments (Gemini, Copilot, etc.)
# Logs timing data to ~/.claude/logs/ai-review-times.csv for optimization.
# Exits with 0 when comments are found, 1 on timeout, 2 on error, 3 when the only bot review is a
# "wasn't able to review any files" decline (PROJ-4148, PROJ-4049, PROJ-4179 — that body used to
# count as a review, so a PR nobody reviewed read as reviewed).

set -euo pipefail

OWNER_REPO="${1:?Usage: poll-ai-reviews.sh <OWNER/REPO> <PR_NUMBER> [MAX_MINUTES] [INTERVAL_SECONDS]}"
PR_NUMBER="${2:?Usage: poll-ai-reviews.sh <OWNER/REPO> <PR_NUMBER> [MAX_MINUTES] [INTERVAL_SECONDS]}"
MAX_MINUTES="${3:-6}"
INTERVAL="${4:-45}"

MAX_SECONDS=$((MAX_MINUTES * 60))
ELAPSED=0
START_TIME=$(date +%s)
LOG_FILE="$HOME/.claude/logs/ai-review-times.csv"

# Ensure log dir and header exist
mkdir -p "$(dirname "$LOG_FILE")"
if [ ! -f "$LOG_FILE" ]; then
  echo "date,repo,pr,elapsed_seconds,result,bot_count" > "$LOG_FILE"
fi

# Known AI bot patterns (case-insensitive match on login)
BOT_PATTERNS="gemini-code-assist|copilot|github-actions|coderabbit|sourcery|sweep"
# A review whose body says the bot reviewed nothing is not a review.
DECLINE_PATTERN="(wasn.t|was not|were not|weren.t) able to review any files|unable to review any files"

echo "Polling PR #${PR_NUMBER} on ${OWNER_REPO} for AI bot reviews..."
echo "Max wait: ${MAX_MINUTES} minutes, checking every ${INTERVAL} seconds"
echo ""

while [ "$ELAPSED" -lt "$MAX_SECONDS" ]; do
  # Check PR review comments (inline comments)
  COMMENTS=$(gh api "repos/${OWNER_REPO}/pulls/${PR_NUMBER}/comments" 2>/dev/null || echo "[]")

  # Check PR reviews (top-level reviews)
  REVIEWS=$(gh api "repos/${OWNER_REPO}/pulls/${PR_NUMBER}/reviews" 2>/dev/null || echo "[]")

  # Filter for bot authors in comments
  BOT_COMMENTS=$(echo "$COMMENTS" | jq -r --arg pat "$BOT_PATTERNS" \
    '[.[] | select(.user.login | test($pat; "i"))] | length' 2>/dev/null || echo "0")

  # Filter for bot authors in reviews
  BOT_REVIEWS=$(echo "$REVIEWS" | jq -r --arg pat "$BOT_PATTERNS" --arg dec "$DECLINE_PATTERN" \
    '[.[] | select(.user.login | test($pat; "i")) | select((.body // "") | test($dec; "i") | not)] | length' 2>/dev/null || echo "0")

  BOT_DECLINES=$(echo "$REVIEWS" | jq -r --arg pat "$BOT_PATTERNS" --arg dec "$DECLINE_PATTERN" \
    '[.[] | select(.user.login | test($pat; "i")) | select((.body // "") | test($dec; "i"))] | length' 2>/dev/null || echo "0")

  TOTAL=$((BOT_COMMENTS + BOT_REVIEWS))

  if [ "$TOTAL" -eq 0 ] && [ "$BOT_DECLINES" -gt 0 ]; then
    ACTUAL=$(($(date +%s) - START_TIME))
    echo "$(date +%Y-%m-%d_%H:%M),${OWNER_REPO},${PR_NUMBER},${ACTUAL},declined,0" >> "$LOG_FILE"
    echo "DECLINED: the bot posted a review saying it was not able to review any files. This is NOT a review."
    echo "Re-request: gh pr edit ${PR_NUMBER} -R ${OWNER_REPO} --add-reviewer @copilot  (then poll .reviews again)"
    exit 3
  fi

  if [ "$TOTAL" -gt 0 ]; then
    ACTUAL=$(($(date +%s) - START_TIME))
    echo "Found ${TOTAL} AI bot review(s) after $((ACTUAL / 60))m $((ACTUAL % 60))s"
    echo ""

    # Log timing
    echo "$(date +%Y-%m-%d_%H:%M),${OWNER_REPO},${PR_NUMBER},${ACTUAL},found,${TOTAL}" >> "$LOG_FILE"

    # Output summary of bot comments
    echo "=== Bot Review Comments ==="
    echo "$COMMENTS" | jq -r --arg pat "$BOT_PATTERNS" \
      '.[] | select(.user.login | test($pat; "i")) | "[\(.user.login)] \(.path):\(.line // .original_line // "general")\n\(.body)\n---"' 2>/dev/null || true

    echo ""
    echo "=== Bot Reviews ==="
    echo "$REVIEWS" | jq -r --arg pat "$BOT_PATTERNS" \
      '.[] | select(.user.login | test($pat; "i")) | "[\(.user.login)] State: \(.state)\n\(.body)\n---"' 2>/dev/null || true

    exit 0
  fi

  MINS=$((ELAPSED / 60))
  echo "  No bot reviews yet... (${MINS}m elapsed)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

# Log timeout
ACTUAL=$(($(date +%s) - START_TIME))
echo "$(date +%Y-%m-%d_%H:%M),${OWNER_REPO},${PR_NUMBER},${ACTUAL},timeout,0" >> "$LOG_FILE"

echo ""
echo "Timeout: No AI bot reviews found after ${MAX_MINUTES} minutes."
echo "The PR may not have AI review bots configured, or they may be slow."
exit 1
