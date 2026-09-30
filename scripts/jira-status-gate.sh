#!/usr/bin/env bash
# jira-status-gate.sh — assert a Jira ticket is in the expected status, and optionally fix it.
#
# DTF's status transitions are prose steps with no gate, so they get skipped: a session can
# reach the draft-PR step with the ticket still sitting in "Att göra", and nobody notices until
# someone looks at the board. This turns that into a check that fails.
#
# Usage:
#   jira-status-gate.sh <TICKET_ID> <EXPECTED_STATUS> [--fix]
#
# Examples:
#   jira-status-gate.sh PROJ-1234 "Pågående"          # assert only, exit 1 on mismatch
#   jira-status-gate.sh PROJ-1234 "Pågående" --fix    # transition if it is not there yet
#
# Exit codes: 0 = in the expected status (or moved there with --fix)
#             1 = wrong status and not fixed
#             2 = could not read the ticket
set -euo pipefail

TICKET="${1:?usage: $0 <TICKET_ID> <EXPECTED_STATUS> [--fix]}"
EXPECTED="${2:?usage: $0 <TICKET_ID> <EXPECTED_STATUS> [--fix]}"
FIX="${3:-}"

# No `exit` in the awk program, and `|| true` on the pipeline. `awk ... {print; exit}`
# closes the pipe while acli is still writing, acli dies of SIGPIPE, `pipefail` turns
# that into 141 and `set -e` kills this script before it can print anything. It is
# racy — it depends on whether acli has finished filling the pipe buffer — so it
# passes on a retry and reads like a fluke. `!seen` gives the same first-match-only
# result while draining the input.
current=$(acli jira workitem view "$TICKET" 2>/dev/null | awk -F': ' '/^Status:/ && !seen {print $2; seen=1}' || true)

if [ -z "$current" ]; then
  echo "GATE ERROR: could not read status for $TICKET" >&2
  exit 2
fi

if [ "$current" = "$EXPECTED" ]; then
  echo "✓ $TICKET is '$EXPECTED'"
  exit 0
fi

if [ "$FIX" = "--fix" ]; then
  echo "→ $TICKET is '$current', expected '$EXPECTED' — transitioning"
  acli jira workitem transition --key "$TICKET" --status "$EXPECTED" --yes >/dev/null 2>&1 || {
    echo "GATE REFUSED: transition of $TICKET to '$EXPECTED' failed. Available transitions:" >&2
    acli jira workitem transition --key "$TICKET" --list 2>&1 | head -10 >&2 || true
    exit 1
  }
  echo "✓ $TICKET moved to '$EXPECTED'"
  exit 0
fi

cat >&2 <<MSG
GATE REFUSED: $TICKET is '$current', expected '$EXPECTED'.

A skipped status transition means the board does not show what is actually happening.
Re-run with --fix, or transition it by hand, before continuing:

  bash ~/.claude/scripts/jira-status-gate.sh $TICKET "$EXPECTED" --fix
MSG
exit 1
