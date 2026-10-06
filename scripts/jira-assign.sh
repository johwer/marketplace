#!/bin/bash
# jira-assign.sh — Assign a Jira work item via the REST API
#
# `acli ... --assignee` fails, so this calls PUT /issue/<KEY>/assignee with
# the ACLI OAuth token from the macOS keychain. With no account id the item is
# assigned to the authenticated user (account id from GET /myself).
#
# Usage:
#   bash ~/.claude/scripts/jira-assign.sh <TICKET_ID> [ACCOUNT_ID]
#
# Examples:
#   bash ~/.claude/scripts/jira-assign.sh PROJ-1234            # assign to me
#   bash ~/.claude/scripts/jira-assign.sh PROJ-1234 <accountId>
#
# Prints the assignee's display name read back from Jira, so the assignment is
# verified, not assumed.
#
# Prerequisites: acli authenticated (OAuth token in keychain), curl, python3

set -euo pipefail

TICKET="${1:?Usage: $0 <TICKET_ID> [ACCOUNT_ID]}"
ACCOUNT_ID="${2:-}"
CLOUD_ID="00000000-0000-0000-0000-000000000000"
API="https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3"

acli jira workitem view "$TICKET" --fields summary > /dev/null 2>&1 || {
    echo "ERROR: Failed to reach Jira for $TICKET. Check acli auth." >&2
    exit 1
}

ACCESS_TOKEN=$(security find-generic-password -s "acli" -w 2>/dev/null | python3 -c "
import sys, base64, gzip, json
d = sys.stdin.read().strip()
d = d[len('go-keyring-base64:'):]
print(json.loads(gzip.decompress(base64.b64decode(d)))['access_token'])
" 2>/dev/null) || {
    echo "ERROR: Failed to extract OAuth token from keychain." >&2
    exit 2
}

if [ -z "$ACCOUNT_ID" ]; then
    ACCOUNT_ID=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API/myself" \
        | python3 -c "import sys, json; print(json.load(sys.stdin).get('accountId', ''))")
    [ -n "$ACCOUNT_ID" ] || { echo "ERROR: GET /myself returned no accountId." >&2; exit 1; }
fi

RESPONSE=$(mktemp)
trap 'rm -f "$RESPONSE"' EXIT

HTTP_CODE=$(curl -s -w "%{http_code}" -o "$RESPONSE" \
    -X PUT \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"accountId\": \"$ACCOUNT_ID\"}" \
    "$API/issue/$TICKET/assignee")

if [ "$HTTP_CODE" != "204" ]; then
    echo "ERROR: HTTP $HTTP_CODE assigning $TICKET" >&2
    cat "$RESPONSE" >&2
    exit 1
fi

ASSIGNEE=$(acli jira workitem view "$TICKET" --fields assignee --json \
    | python3 -c "import sys, json; a = json.load(sys.stdin)['fields'].get('assignee') or {}; print(a.get('displayName', ''))")
[ -n "$ASSIGNEE" ] || { echo "ERROR: $TICKET still has no assignee after PUT." >&2; exit 1; }
echo "$TICKET: assigned to $ASSIGNEE"
