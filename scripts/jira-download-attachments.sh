#!/bin/bash
# jira-download-attachments.sh — Download all attachments from a Jira ticket
#
# Uses the ACLI OAuth token from macOS keychain to download via the public
# Atlassian API. Falls back to opening Chrome if the API download fails.
#
# Usage:
#   bash ~/.claude/scripts/jira-download-attachments.sh <TICKET_ID> [OUTPUT_DIR]
#
# Output:
#   Downloads to OUTPUT_DIR (default: ~/Downloads/<TICKET_ID>/)
#   Prints downloaded file paths to stdout, one per line.
#
# Prerequisites:
#   - acli installed and authenticated (OAuth token in keychain)
#   - curl, python3, security (macOS)

set -euo pipefail

TICKET="${1:?Usage: $0 <TICKET_ID> [OUTPUT_DIR]}"
OUTPUT_DIR="${2:-$HOME/Downloads/$TICKET}"
CLOUD_ID="4f617dfc-e4b4-4019-826c-6d9df112d610"
API_BASE="https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/attachment/content"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Step 1: Refresh the ACLI OAuth token by running a lightweight command
acli jira workitem view "$TICKET" --fields summary > /dev/null 2>&1 || {
    echo "ERROR: Failed to reach Jira for $TICKET. Check acli auth." >&2
    exit 1
}

# Step 2: List attachments
ATTACHMENTS=$(acli jira workitem attachment list --key "$TICKET" 2>/dev/null)
if [ -z "$ATTACHMENTS" ] || echo "$ATTACHMENTS" | grep -qi "No attachments"; then
    echo "NO_ATTACHMENTS"
    exit 0
fi

# Parse attachment IDs and filenames from the table output
# Format: │ 57823         │ image-20260227-141332.png │ 100895          │
PARSED=$(echo "$ATTACHMENTS" | grep '│' | grep -v 'Attachment' | grep -v '─' | while IFS='│' read -r _ id name size _; do
    id=$(echo "$id" | xargs)
    name=$(echo "$name" | xargs)
    size=$(echo "$size" | xargs)
    [ -n "$id" ] && [ -n "$name" ] && echo "$id|$name|$size"
done)

if [ -z "$PARSED" ]; then
    echo "NO_ATTACHMENTS"
    exit 0
fi

# Step 3: Extract OAuth token from macOS keychain
ACCESS_TOKEN=$(security find-generic-password -s "acli" -w 2>/dev/null | python3 -c "
import sys, base64, gzip, json
d = sys.stdin.read().strip()
d = d[len('go-keyring-base64:'):]
print(json.loads(gzip.decompress(base64.b64decode(d)))['access_token'])
" 2>/dev/null) || {
    echo "ERROR: Failed to extract OAuth token from keychain." >&2
    echo "FALLBACK: Open attachments in Chrome manually." >&2
    exit 2
}

# Step 4: Download each attachment
DOWNLOADED=0
FAILED=0
while IFS='|' read -r att_id att_name att_size; do
    [ -z "$att_id" ] && continue

    OUTPUT_FILE="$OUTPUT_DIR/$att_name"

    # Download via public API
    HTTP_CODE=$(curl -s -L -w "%{http_code}" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -o "$OUTPUT_FILE" \
        "$API_BASE/$att_id" 2>/dev/null)

    if [ "$HTTP_CODE" = "200" ] && [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
        echo "$OUTPUT_FILE"
        DOWNLOADED=$((DOWNLOADED + 1))
    else
        echo "FAILED: $att_name (HTTP $HTTP_CODE)" >&2
        rm -f "$OUTPUT_FILE"
        FAILED=$((FAILED + 1))
    fi
done <<< "$PARSED"

if [ "$FAILED" -gt 0 ] && [ "$DOWNLOADED" -eq 0 ]; then
    echo "ERROR: All downloads failed. Token may be expired — try running any acli command first." >&2
    exit 2
fi

echo "DONE: $DOWNLOADED downloaded, $FAILED failed" >&2
