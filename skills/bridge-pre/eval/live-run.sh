#!/usr/bin/env bash
# Usage: live-run.sh <live-dir> <head-sha> <variant> <extra-prompt-file|-> [model]
# One repo-access reviewer on a live PR (no expected.md yet); output lands in <live-dir>/reviews/<variant>.md for adjudication.
set -euo pipefail
skill="$(cd "$(dirname "$0")/.." && pwd)"
live=$1 head=$2 variant=$3 extra=$4 model=${5:-claude-sonnet-5-5}
repo="${BRIDGE_REPO:-$HOME/Documents/Repo}"; out="$live/reviews"; mkdir -p "$out"
cat "$skill/prompts/reviewer-repo.md" > "$out/$variant.system.md"; [[ $extra == - ]] || cat "$extra" >> "$out/$variant.system.md"
{ printf 'Head commit: %s\n\n' "$head"; cat "$live/input.md"; } > "$out/$variant.input.md"
( cd "$repo" && timeout 900 claude -p --model "$model" --output-format json --permission-mode dontAsk \
    --tools "Bash" --allowedTools "Bash(git show:*)" "Bash(git grep:*)" "Bash(git ls-tree:*)" \
    --max-budget-usd "${BRIDGE_MAX_USD_REVIEWER:-3}" --system-prompt "$(cat "$out/$variant.system.md")" < "$out/$variant.input.md" ) > "$out/$variant.raw.json"
jq -r .result "$out/$variant.raw.json" > "$out/$variant.md"
echo "$variant \$$(jq -r .total_cost_usd "$out/$variant.raw.json")"
