#!/usr/bin/env bash
# Usage: critic.sh <brief.md> <advisors-dir> <out-prefix> [model]
# Ranks the advisors' points without code access: <out-prefix>.json holds a shortlist (at most 8) and a weak list.
# Nothing is dropped; show the shortlist first and the weak list collapsed. Prints the cost in USD.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
brief=$1 advisors=$2 out=$3 model=${4:-claude-sonnet-5-5}
mkdir -p "$(dirname "$out")"
case "$(cd "$(dirname "$out")" && pwd)" in "$(cd "$advisors" && pwd)") echo "out-prefix must not be inside the advisors dir" >&2; exit 2 ;; esac
{ echo "=== BRIEF ==="; cat "$brief"; echo
  for a in "$advisors"/*@*@*.md; do [[ -f $a ]] || continue; echo "=== ADVISOR $(basename "$a" .md) ==="; cat "$a"; echo; done; } > "$out.input.md"
[[ $(wc -c < "$out.input.md") -lt 800000 ]] || { echo "critic input over 800 kB, refusing" >&2; exit 2; }
( cd "$(mktemp -d)" && timeout "${BRIDGE_CRITIC_TIMEOUT:-300}" claude -p --model "$model" --output-format json --tools "" \
    --max-budget-usd "${BRIDGE_MAX_USD_CRITIC:-1}" --system-prompt "$(cat "$root/prompts/critic.md")" < "$out.input.md" ) > "$out.raw.json"
jq -r '.result' "$out.raw.json" | grep '^{' | tail -1 > "$out.json"
jq -e .shortlist "$out.json" >/dev/null || { echo "critic output unparseable: $out.raw.json" >&2; exit 4; }
jq -r '.total_cost_usd' "$out.raw.json"
