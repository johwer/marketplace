#!/usr/bin/env bash
# analyze-patterns.sh — Analyze tool usage logs and generate instinct files
# Runs on-demand: bash ~/.claude/scripts/analyze-patterns.sh [--since YYYY-MM-DD]
#
# Reads: ~/.claude/logs/tool-usage.csv
# Writes: ~/.claude/instincts/<project-hash>/INSTINCTS.md

set -euo pipefail

LOG_FILE="$HOME/.claude/logs/tool-usage.csv"
SINCE="${2:-$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)}"

if [ ! -f "$LOG_FILE" ]; then
  echo "No tool usage log found at $LOG_FILE"
  exit 0
fi

# Determine project scope from git remote (or "global")
PROJECT_HASH="global"
if git rev-parse --is-inside-work-tree &>/dev/null; then
  REMOTE=$(git remote get-url origin 2>/dev/null || echo "local")
  PROJECT_HASH=$(echo "$REMOTE" | shasum -a 256 | cut -c1-8)
fi

INSTINCT_DIR="$HOME/.claude/instincts/$PROJECT_HASH"
mkdir -p "$INSTINCT_DIR"

echo "=== Pattern Analysis ==="
echo "Log: $LOG_FILE"
echo "Since: $SINCE"
echo "Project: $PROJECT_HASH"
echo ""

# --- Pattern 1: Repeated file reads (same file read 3+ times = should be in context) ---
echo "## Frequently Read Files (possible context gaps)"
awk -F',' -v since="$SINCE" '
  $1 >= since && $3 == "Read" { count[$4]++ }
  END { for (f in count) if (count[f] >= 3) printf "  %3dx  %s\n", count[f], f }
' "$LOG_FILE" | sort -rn

echo ""

# --- Pattern 2: Edit-then-Edit (same file edited multiple times = iteration/struggle) ---
echo "## Files Edited Multiple Times (possible struggle points)"
awk -F',' -v since="$SINCE" '
  $1 >= since && ($3 == "Edit" || $3 == "Write") { count[$4]++ }
  END { for (f in count) if (count[f] >= 3) printf "  %3dx  %s\n", count[f], f }
' "$LOG_FILE" | sort -rn

echo ""

# --- Pattern 3: Bash command frequency (repeated commands = should be scripted) ---
echo "## Frequent Bash Commands (candidates for scripts/aliases)"
awk -F',' -v since="$SINCE" '
  $1 >= since && $3 == "Bash" { count[$4]++ }
  END { for (c in count) if (count[c] >= 3) printf "  %3dx  %s\n", count[c], c }
' "$LOG_FILE" | sort -rn

echo ""

# --- Pattern 4: Tool sequence patterns (what follows what) ---
echo "## Common Tool Sequences"
awk -F',' -v since="$SINCE" '
  $1 >= since {
    if (prev != "") {
      pair = prev " -> " $3
      count[pair]++
    }
    prev = $3
  }
  END { for (p in count) if (count[p] >= 5) printf "  %3dx  %s\n", count[p], p }
' "$LOG_FILE" | sort -rn

echo ""

# --- Pattern 5: Session length (tool calls per session) ---
echo "## Session Sizes (tool calls per session)"
awk -F',' -v since="$SINCE" '
  $1 >= since && NR > 1 { count[$2]++ }
  END {
    total = 0; sessions = 0; max = 0
    for (s in count) {
      total += count[s]; sessions++
      if (count[s] > max) max = count[s]
    }
    if (sessions > 0) printf "  Sessions: %d  |  Avg tools/session: %d  |  Max: %d\n", sessions, total/sessions, max
  }
' "$LOG_FILE"

echo ""

# --- Generate instinct summary ---
INSTINCT_FILE="$INSTINCT_DIR/INSTINCTS.md"
{
  echo "# Instincts — Project $PROJECT_HASH"
  echo ""
  echo "> Auto-generated $(date '+%Y-%m-%d %H:%M') from tool usage analysis since $SINCE"
  echo ""
  echo "## How to Use"
  echo ""
  echo "These patterns were detected from your tool usage logs. Review them and:"
  echo "- **Promote** valuable patterns to skills or conventions"
  echo "- **Dismiss** patterns that are noise"
  echo "- Run \`/evolve\` to cluster related instincts into skill candidates"
  echo ""
  echo "## Detected Patterns"
  echo ""

  awk -F',' -v since="$SINCE" '
    $1 >= since && $3 == "Read" { count[$4]++ }
    END { for (f in count) if (count[f] >= 5) printf "- **Context gap:** `%s` read %dx — consider adding to CLAUDE.md or a skill\n", f, count[f] }
  ' "$LOG_FILE"

  awk -F',' -v since="$SINCE" '
    $1 >= since && ($3 == "Edit" || $3 == "Write") { count[$4]++ }
    END { for (f in count) if (count[f] >= 4) printf "- **Struggle point:** `%s` edited %dx — check if conventions are unclear\n", f, count[f] }
  ' "$LOG_FILE"

  awk -F',' -v since="$SINCE" '
    $1 >= since && $3 == "Bash" { count[$4]++ }
    END { for (c in count) if (count[c] >= 5) printf "- **Script candidate:** `%s` run %dx — wrap in a script\n", c, count[c] }
  ' "$LOG_FILE"
} > "$INSTINCT_FILE"

echo "Instinct summary written to $INSTINCT_FILE"
echo "Run: cat $INSTINCT_FILE"
