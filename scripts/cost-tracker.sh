#!/usr/bin/env bash
# cost-tracker.sh — Track and report session costs based on tool usage
# Usage:
#   bash ~/.claude/scripts/cost-tracker.sh report [--since YYYY-MM-DD]
#   bash ~/.claude/scripts/cost-tracker.sh session <session_id>
#   bash ~/.claude/scripts/cost-tracker.sh top-sessions [N]
#
# Reads: ~/.claude/logs/tool-usage.csv
# Cost model: relative units per tool call (Agent=20, Edit/Write=3, Bash=2, Read/Grep/Glob=1)

set -euo pipefail

LOG_FILE="$HOME/.claude/logs/tool-usage.csv"
CMD="${1:-report}"

if [ ! -f "$LOG_FILE" ]; then
  echo "No tool usage log found. Costs are tracked via PostToolUse hooks."
  exit 0
fi

case "$CMD" in
  report)
    SINCE="${3:-$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)}"
    echo "=== Cost Report (since $SINCE) ==="
    echo ""

    # Tool call counts
    echo "── Tool Usage ──"
    awk -F',' -v since="$SINCE" '
      NR > 1 && $1 >= since { tools[$3]++; total++ }
      END {
        printf "  Total calls: %d\n\n", total
        for (t in tools) printf "  %-12s %5d calls\n", t, tools[t]
      }
    ' "$LOG_FILE" | sort -t: -k2 -rn
    echo ""

    # Session summary
    echo "── Sessions ──"
    awk -F',' -v since="$SINCE" '
      NR > 1 && $1 >= since { sessions[$2]++ }
      END {
        n = 0; total = 0
        for (s in sessions) { n++; total += sessions[s] }
        printf "  Total sessions: %d\n", n
        if (n > 0) printf "  Avg tools/session: %d\n", total/n
      }
    ' "$LOG_FILE"
    echo ""

    # Estimated cost distribution
    echo "── Cost Estimate (relative units) ──"
    awk -F',' -v since="$SINCE" '
      function cost(tool) {
        if (tool == "Agent") return 20
        if (tool == "Edit" || tool == "Write") return 3
        if (tool == "Bash") return 2
        if (tool ~ /^Task/) return 1
        if (tool == "Read" || tool == "Grep" || tool == "Glob") return 1
        return 2
      }
      NR > 1 && $1 >= since {
        c = cost($3)
        total += c
        by_tool[$3] += c
      }
      END {
        printf "  Total: %d units\n\n", total
        for (t in by_tool) printf "  %-12s %5d units (%4.1f%%)\n", t, by_tool[t], (by_tool[t]/total)*100
      }
    ' "$LOG_FILE"
    ;;

  session)
    SID="${2:-}"
    if [ -z "$SID" ]; then
      echo "Usage: cost-tracker.sh session <session_id>"
      exit 1
    fi
    echo "=== Session: $SID ==="
    awk -F',' -v sid="$SID" '
      $2 == sid { print "  " $1 " " $3 ": " $4; count++ }
      END { printf "\n  Total tool calls: %d\n", count }
    ' "$LOG_FILE"
    ;;

  top-sessions)
    N="${2:-10}"
    echo "=== Top $N Sessions by Tool Usage ==="
    awk -F',' '
      NR > 1 { count[$2]++; if (!first[$2]) first[$2] = $1 }
      END {
        for (s in count) printf "%s,%d,%s\n", s, count[s], first[s]
      }
    ' "$LOG_FILE" | sort -t',' -k2 -rn | head -"$N" | while IFS=',' read -r sid cnt dt; do
      printf "  %-40s %4d calls  (%s)\n" "$sid" "$cnt" "$dt"
    done
    ;;

  *)
    echo "Usage: cost-tracker.sh {report|session|top-sessions} [args]"
    exit 1
    ;;
esac
