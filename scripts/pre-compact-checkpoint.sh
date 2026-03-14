#!/bin/bash
# PreCompact hook — saves a checkpoint before context compression
# Reads the transcript and context state, writes CHECKPOINT.md to the project dir.
# This ensures critical decisions/state survive compression.

input=$(cat)

SESSION_ID=$(echo "$input" | jq -r '.session_id // empty')
CWD=$(echo "$input" | jq -r '.cwd // empty')
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // empty')
TRIGGER=$(echo "$input" | jq -r '.trigger // "unknown"')

# Read context % from the shared file written by statusline
CONTEXT_FILE="/tmp/claude-context-${SESSION_ID:-default}.json"
if [ -f "$CONTEXT_FILE" ]; then
  PCT=$(jq -r '.used_percentage // "?"' "$CONTEXT_FILE" 2>/dev/null)
  TOKENS_IN=$(jq -r '.total_input_tokens // "?"' "$CONTEXT_FILE" 2>/dev/null)
  TOKENS_OUT=$(jq -r '.total_output_tokens // "?"' "$CONTEXT_FILE" 2>/dev/null)
else
  PCT="?"
  TOKENS_IN="?"
  TOKENS_OUT="?"
fi

# Determine checkpoint location
CHECKPOINT_DIR="$CWD"
if [ ! -d "$CHECKPOINT_DIR" ]; then
  CHECKPOINT_DIR="/tmp"
fi
CHECKPOINT_FILE="$CHECKPOINT_DIR/CHECKPOINT.md"

# Extract recent assistant messages from transcript (last ~50 lines for summary)
RECENT_CONTEXT=""
if [ -f "$TRANSCRIPT" ]; then
  RECENT_CONTEXT=$(tail -100 "$TRANSCRIPT" | jq -r '
    select(.type == "message" and .role == "assistant") |
    .content | if type == "array" then
      map(select(.type == "text") | .text) | join("\n")
    elif type == "string" then .
    else empty end
  ' 2>/dev/null | tail -80)
fi

# Write checkpoint
cat > "$CHECKPOINT_FILE" << EOF
# Context Checkpoint

> Auto-generated before ${TRIGGER} compaction at $(date '+%Y-%m-%d %H:%M:%S')
> Context usage: ${PCT}% | Input tokens: ${TOKENS_IN} | Output tokens: ${TOKENS_OUT}
> Session: ${SESSION_ID}

## How to use this file

Read this file at the start of your next turn after compression.
It captures the state right before context was compressed.
Delete this file once you've absorbed the context.

## Recent assistant context

\`\`\`
${RECENT_CONTEXT:-No transcript data available}
\`\`\`
EOF

# Log that checkpoint was created
echo "[pre-compact] Checkpoint saved to $CHECKPOINT_FILE (${TRIGGER}, ${PCT}% context)" >&2
