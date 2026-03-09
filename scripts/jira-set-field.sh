#!/bin/bash
# jira-set-field.sh — Set any Jira field (including custom fields) via REST API
#
# Uses the ACLI OAuth token from macOS keychain to call the Jira REST API
# directly. This covers fields that ACLI doesn't expose (e.g., story points).
#
# Usage:
#   bash ~/.claude/scripts/jira-set-field.sh <TICKET_ID> <FIELD_ID> <VALUE>
#
# Examples:
#   # Set story point estimate (customfield_10437)
#   bash ~/.claude/scripts/jira-set-field.sh PROJ-123 customfield_10437 4
#
#   # Set a text custom field
#   bash ~/.claude/scripts/jira-set-field.sh PROJ-123 customfield_10999 '"some text"'
#
# Prerequisites:
#   - acli installed and authenticated (OAuth token in keychain)
#   - curl, python3, security (macOS)
#
# Known field IDs (PLRS project):
#   customfield_10437  Story point estimate
#   customfield_10124  Story Points (legacy)

set -euo pipefail

TICKET="${1:?Usage: $0 <TICKET_ID> <FIELD_ID> <VALUE>}"
FIELD_ID="${2:?Usage: $0 <TICKET_ID> <FIELD_ID> <VALUE>}"
VALUE="${3:?Usage: $0 <TICKET_ID> <FIELD_ID> <VALUE>}"
CLOUD_ID="4f617dfc-e4b4-4019-826c-6d9df112d610"

# Refresh ACLI token by running a lightweight command
acli jira workitem view "$TICKET" --fields summary > /dev/null 2>&1 || {
    echo "ERROR: Failed to reach Jira for $TICKET. Check acli auth." >&2
    exit 1
}

# Extract OAuth token from macOS keychain
ACCESS_TOKEN=$(security find-generic-password -s "acli" -w 2>/dev/null | python3 -c "
import sys, base64, gzip, json
d = sys.stdin.read().strip()
d = d[len('go-keyring-base64:'):]
print(json.loads(gzip.decompress(base64.b64decode(d)))['access_token'])
" 2>/dev/null) || {
    echo "ERROR: Failed to extract OAuth token from keychain." >&2
    exit 2
}

# Set the field via REST API
HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/jira-set-field-response.json \
    -X PUT \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"fields\": {\"$FIELD_ID\": $VALUE}}" \
    "https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/issue/$TICKET")

if [ "$HTTP_CODE" = "204" ]; then
    echo "$TICKET: $FIELD_ID set to $VALUE"
else
    echo "ERROR: HTTP $HTTP_CODE for $TICKET" >&2
    cat /tmp/jira-set-field-response.json >&2 2>/dev/null
    exit 1
fi
