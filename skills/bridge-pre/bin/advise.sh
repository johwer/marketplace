#!/usr/bin/env bash
# Usage: advise.sh <brief.md> <lens> <model> <out-prefix> [effort]
# Writes <out-prefix>.md (answer) and <out-prefix>.json (raw); prints cost in USD.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
brief=$1 lens=$2 model=$3 out=$4 effort=${5:-medium}
budget="${BRIDGE_MAX_USD_PER_ADVISOR:-0.50}"
lens_file="$root/lenses/$lens.md"; [[ -f $lens ]] && lens_file=$lens
[[ -f $lens_file ]] || { echo "unknown lens: $lens" >&2; exit 2; }
[[ -f $brief ]] || { echo "brief not found: $brief" >&2; exit 2; }
case $model in
  claude-*|sonnet|opus|haiku|fable) ;;
  *) echo "provider for '$model' not enabled: external advisors wait on company approval" >&2; exit 3 ;;
esac
system="$(cat "${BRIDGE_ADVISOR_PROMPT:-$root/prompts/advisor.md}"; echo; cat "$lens_file")"
work="$(mktemp -d)"
( cd "$work" && timeout "${BRIDGE_ADVISOR_TIMEOUT:-180}" claude -p --model "$model" --output-format json --tools "" --effort "$effort" --max-budget-usd "$budget" --system-prompt "$system" < "$brief" ) > "$out.json"
rm -rf "$work"
jq -r '.result' "$out.json" > "$out.md"
jq -r '.total_cost_usd' "$out.json"
