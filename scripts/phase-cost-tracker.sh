#!/usr/bin/env bash
# phase-cost-tracker.sh — Track and report costs per Dream Team phase
#
# Usage:
#   bash ~/.claude/scripts/phase-cost-tracker.sh log <session_id> <phase> <agent> <tool_uses> <note>
#   bash ~/.claude/scripts/phase-cost-tracker.sh report [session_id]
#   bash ~/.claude/scripts/phase-cost-tracker.sh compare [--last N]
#
# Reads/writes: ~/.claude/logs/phase-costs.csv
# Format: timestamp,session_id,phase,agent,tool_uses,note

set -euo pipefail

LOG_FILE="$HOME/.claude/logs/phase-costs.csv"
CMD="${1:-report}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Write header if file doesn't exist
if [ ! -f "$LOG_FILE" ]; then
  echo "timestamp,session_id,phase,agent,tool_uses,note" > "$LOG_FILE"
fi

case "$CMD" in
  log)
    SESSION_ID="${2:-unknown}"
    PHASE="${3:-unknown}"
    AGENT="${4:-lead}"
    TOOL_USES="${5:-0}"
    NOTE="${6:-}"
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Escape commas in note
    NOTE=$(echo "$NOTE" | tr ',' ';' | tr '\n' ' ' | cut -c1-200)
    echo "${TIMESTAMP},${SESSION_ID},${PHASE},${AGENT},${TOOL_USES},${NOTE}" >> "$LOG_FILE"
    echo "Logged: ${PHASE} | ${AGENT} | ${TOOL_USES} tool uses"
    ;;

  report)
    SESSION_ID="${2:-}"
    if [ -z "$SESSION_ID" ]; then
      # Show all sessions
      echo "=== Phase Cost Report (all sessions) ==="
      echo ""
      awk -F',' 'NR > 1 {
        sessions[$2] = 1
        phases[$2","$3] += $5
        total[$2] += $5
        agents[$2","$3","$4] += $5
      }
      END {
        for (s in sessions) {
          printf "Session: %s  |  Total: %d tool uses\n", s, total[s]
          # Print phases for this session
          for (key in phases) {
            split(key, parts, SUBSEP)
            if (parts[1] == s) {
              printf "  %-25s %4d tool uses\n", parts[2], phases[key]
            }
          }
          printf "\n"
        }
      }' "$LOG_FILE"
    else
      # Show specific session
      echo "=== Phase Costs: $SESSION_ID ==="
      echo ""
      awk -F',' -v sid="$SESSION_ID" '
        $2 == sid {
          printf "  %-12s %-20s %-10s %4d uses  %s\n", $1, $3, $4, $5, $6
          total += $5
        }
        END { printf "\n  TOTAL: %d tool uses\n", total }
      ' "$LOG_FILE"
    fi
    ;;

  compare)
    N="${3:-5}"
    echo "=== Phase Cost Comparison (last $N sessions) ==="
    echo ""
    echo "Phase                  Avg Uses   Min   Max   Sessions"
    echo "─────────────────────  ────────   ───   ───   ────────"
    # Get last N sessions
    SESSIONS=$(awk -F',' 'NR > 1 { print $2 }' "$LOG_FILE" | sort -u | tail -"$N")
    # Calculate stats per phase
    awk -F',' -v sessions="$SESSIONS" '
      BEGIN { split(sessions, s_arr, "\n") }
      NR > 1 {
        found = 0
        for (i in s_arr) { if (s_arr[i] == $2) found = 1 }
        if (!found) next
        phase = $3
        uses = $5
        count[phase]++
        sum[phase] += uses
        if (!(phase in min_val) || uses < min_val[phase]) min_val[phase] = uses
        if (uses > max_val[phase]) max_val[phase] = uses
        sess[phase,$2] = 1
      }
      END {
        for (p in count) {
          # Count unique sessions
          ns = 0
          for (key in sess) {
            split(key, parts, SUBSEP)
            if (parts[1] == p) ns++
          }
          printf "%-23s %6d   %4d  %4d   %d\n", p, sum[p]/count[p], min_val[p], max_val[p], ns
        }
      }
    ' "$LOG_FILE" | sort -k2 -rn
    ;;

  *)
    echo "Usage: phase-cost-tracker.sh {log|report|compare} [args]"
    exit 1
    ;;
esac
