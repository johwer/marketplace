#!/bin/bash
# memory-health.sh — Quick memory health check (runs outside Claude, 0 token cost)
# Usage: bash ~/.claude/scripts/memory-health.sh [project-path]
set -eo pipefail

# Find memory directory
PROJECT_PATH="${1:-}"
if [[ -z "$PROJECT_PATH" ]]; then
  # Auto-detect from dtf-config
  MONOREPO=$(jq -r '.paths.monorepo // empty' ~/.claude/dtf-config.json 2>/dev/null)
  if [[ -n "$MONOREPO" ]]; then
    # Convert path to Claude project format (replace / with -)
    SAFE_PATH=$(echo "$MONOREPO" | sed 's|^/||' | sed 's|/|-|g')
    MEMORY_DIR="$HOME/.claude/projects/-$SAFE_PATH/memory"
    # Fallback: try without leading dash
    [[ ! -d "$MEMORY_DIR" ]] && MEMORY_DIR="$HOME/.claude/projects/$SAFE_PATH/memory"
  fi
fi

if [[ -z "${MEMORY_DIR:-}" ]] || [[ ! -d "$MEMORY_DIR" ]]; then
  # Try to find any memory directory
  MEMORY_DIR=$(find ~/.claude/projects -name "MEMORY.md" -exec dirname {} \; 2>/dev/null | head -1)
fi

if [[ -z "$MEMORY_DIR" ]] || [[ ! -d "$MEMORY_DIR" ]]; then
  echo "  ✗ No memory directory found"
  exit 1
fi

echo ""
echo "  🧹 Memory Health Check"
echo "  ─────────────────────────────────────"
echo ""

# 1. MEMORY.md size
MEMORY_FILE="$MEMORY_DIR/MEMORY.md"
if [[ -f "$MEMORY_FILE" ]]; then
  LINES=$(wc -l < "$MEMORY_FILE")
  WORDS=$(wc -w < "$MEMORY_FILE")
  TOKENS=$(echo "$WORDS * 1.3" | bc | cut -d. -f1)

  STATUS="✓"
  NOTE=""
  if [[ $LINES -gt 180 ]]; then
    STATUS="🔴"
    NOTE=" — CRITICAL: approaching 200-line truncation!"
  elif [[ $LINES -gt 150 ]]; then
    STATUS="⚠️ "
    NOTE=" — getting close to truncation limit"
  elif [[ $TOKENS -gt 1500 ]]; then
    STATUS="⚠️ "
    NOTE=" — over 1,500 token budget"
  fi

  printf "  %s MEMORY.md:            %d lines / %d tokens%s\n" "$STATUS" "$LINES" "$TOKENS" "$NOTE"
else
  echo "  ✗ MEMORY.md not found"
fi

# 2. Individual memory files
FILE_COUNT=0
TOTAL_TOKENS=0
LARGE_FILES=""
for f in "$MEMORY_DIR"/*.md; do
  [[ ! -f "$f" ]] && continue
  [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
  FILE_COUNT=$((FILE_COUNT + 1))
  WORDS=$(wc -w < "$f")
  TOKENS=$(echo "$WORDS * 1.3" | bc | cut -d. -f1)
  TOTAL_TOKENS=$((TOTAL_TOKENS + TOKENS))
  LINES=$(wc -l < "$f")
  if [[ $LINES -gt 200 ]]; then
    LARGE_FILES="$LARGE_FILES\n    ⚠️  $(basename "$f"): $LINES lines ($TOKENS tokens)"
  fi
done

printf "  Memory files:          %d files / %d tokens total\n" "$FILE_COUNT" "$TOTAL_TOKENS"

# 3. dream-team-learnings
LEARNINGS="$MEMORY_DIR/dream-team-learnings.md"
if [[ -f "$LEARNINGS" ]]; then
  L_LINES=$(wc -l < "$LEARNINGS")
  L_WORDS=$(wc -w < "$LEARNINGS")
  L_TOKENS=$(echo "$L_WORDS * 1.3" | bc | cut -d. -f1)
  L_STATUS="✓"
  L_NOTE=""
  if [[ $L_LINES -gt 500 ]]; then
    L_STATUS="⚠️ "
    L_NOTE=" — consider archiving processed entries"
  fi
  printf "  %s dream-team-learnings: %d lines / %d tokens%s\n" "$L_STATUS" "$L_LINES" "$L_TOKENS" "$L_NOTE"
fi

# 4. Large files
if [[ -n "$LARGE_FILES" ]]; then
  echo ""
  echo "  Large files (> 200 lines):"
  echo -e "$LARGE_FILES"
fi

# 5. Cost per prompt
echo ""
echo "  ─────────────────────────────────────"
PROMPT_COST=$TOKENS
printf "  Cost per prompt:       ~%d tokens (from MEMORY.md)\n" "$PROMPT_COST"
printf "  Monthly estimate:      ~%dk tokens (at 100 prompts/day)\n" $(( PROMPT_COST * 100 * 30 / 1000 ))

# 6. Suggestions
echo ""
SUGGESTIONS=0

if [[ ${TOKENS:-0} -gt 1500 ]]; then
  SUGGESTIONS=$((SUGGESTIONS + 1))
  echo "  💡 $SUGGESTIONS. Trim MEMORY.md — move detailed content to individual files"
fi

if [[ -n "$LARGE_FILES" ]]; then
  SUGGESTIONS=$((SUGGESTIONS + 1))
  echo "  💡 $SUGGESTIONS. Archive large memory files (see above)"
fi

if [[ -f "$LEARNINGS" ]] && [[ $(wc -l < "$LEARNINGS") -gt 500 ]]; then
  SUGGESTIONS=$((SUGGESTIONS + 1))
  echo "  💡 $SUGGESTIONS. Run /retro-proposals then archive old learnings"
fi

# Check for potentially stale project memories
STALE=0
for f in "$MEMORY_DIR"/*.md; do
  [[ ! -f "$f" ]] && continue
  NAME=$(basename "$f")
  [[ "$NAME" == "MEMORY.md" ]] && continue
  [[ "$NAME" == "dream-team-learnings.md" ]] && continue
  # Check if file hasn't been modified in 90 days
  if [[ $(find "$f" -mtime +90 2>/dev/null | wc -l) -gt 0 ]]; then
    STALE=$((STALE + 1))
  fi
done
if [[ $STALE -gt 0 ]]; then
  SUGGESTIONS=$((SUGGESTIONS + 1))
  echo "  💡 $SUGGESTIONS. Review $STALE memory file(s) not updated in 90+ days"
fi

if [[ $SUGGESTIONS -eq 0 ]]; then
  echo "  ✓ Memory is healthy — no action needed"
fi

echo ""
