#!/bin/bash
# Claude Code status line — shows model, context %, cost, and agent name
# Receives JSON on stdin after every assistant message.
# Also writes context % to a shared file so hooks (PreCompact) can read it.

input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
REMAINING=$(echo "$input" | jq -r '.context_window.remaining_percentage // 100' | cut -d. -f1)
PCT=$((100 - REMAINING))
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
AGENT=$(echo "$input" | jq -r '.agent.name // empty')
SESSION_ID=$(echo "$input" | jq -r '.session_id // empty')

# Write context state to shared file for hooks to read
CONTEXT_FILE="/tmp/claude-context-${SESSION_ID:-default}.json"
echo "$input" | jq '{
  used_percentage: (.context_window.used_percentage // 0),
  remaining_percentage: (.context_window.remaining_percentage // 100),
  total_input_tokens: (.context_window.total_input_tokens // 0),
  total_output_tokens: (.context_window.total_output_tokens // 0),
  context_window_size: (.context_window.context_window_size // 0),
  timestamp: now | todate
}' > "$CONTEXT_FILE" 2>/dev/null

# Context bar with color thresholds
if [ "$PCT" -ge 90 ]; then
  CTX_ICON="🔴"
elif [ "$PCT" -ge 70 ]; then
  CTX_ICON="🟡"
else
  CTX_ICON="🟢"
fi

# Format cost (round to 2 decimal places)
COST_FMT=$(printf "%.2f" "$COST" 2>/dev/null || echo "$COST")

# Build output
OUT="${CTX_ICON} ${PCT}% ctx"
OUT="$OUT  |  ${MODEL}"
OUT="$OUT  |  \$${COST_FMT}"

if [ -n "$AGENT" ]; then
  OUT="$OUT  |  ${AGENT}"
fi

echo "$OUT"
