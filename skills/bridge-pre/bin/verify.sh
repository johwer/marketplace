#!/usr/bin/env bash
# Usage: verify.sh <brief.md> <advisors-dir> <repo-dir> <out-prefix> [base-sha] [model]
# A stronger model with read-only repo access sorts the advisors' points into confirmed / refuted / unverified.
# With base-sha it reads the code at that commit through git only (no checkout); without, the working tree.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
brief=$1 advisors=$2 repo=$3 out=$4 base=${5:-} model=${6:-claude-opus-5-5}
budget="${BRIDGE_MAX_USD_VERIFIER:-3}"
mkdir -p "$(dirname "$out")"
input="$out.input.md"
case "$(cd "$(dirname "$out")" && pwd)" in "$(cd "$advisors" && pwd)") echo "out-prefix must not be inside the advisors dir" >&2; exit 2 ;; esac
{
  echo "=== BRIEF ==="; cat "$brief"; echo
  for a in "$advisors"/*@*@*.md; do
    [[ -f $a && $a != "$out"* ]] || continue
    echo "=== ADVISOR $(basename "$a" .md) ==="; cat "$a"; echo
  done
  if [[ -n $base ]]; then
    echo "=== CODE ACCESS ==="
    echo "Read the code as it was at commit $base, through git only: git show $base:<path>, git grep -n <pattern> $base, git ls-tree -r --name-only $base <dir>. Do not use the working tree; it is a later version. You are already in the repository. Run each command as one plain git command with the full sha written out, exactly like: git show $base:services/X/File.cs. No cd, no shell variables, no git -C, no pipes or chaining: anything else is denied."
  fi
} > "$input"
[[ $(wc -c < "$input") -lt 500000 ]] || { echo "verifier input over 500 kB, refusing: $input" >&2; exit 2; }
if [[ -n $base ]]; then
  tools=(--tools "Bash" --allowedTools "Bash(git show:*)" "Bash(git grep:*)" "Bash(git ls-tree:*)" "Bash(git log:*)")
else
  tools=(--tools "Read,Grep,Glob" --allowedTools "Read" "Grep" "Glob")
fi
( cd "$repo" && timeout "${BRIDGE_VERIFIER_TIMEOUT:-900}" claude -p --model "$model" --output-format json --permission-mode dontAsk "${tools[@]}" \
    --max-budget-usd "$budget" --system-prompt "$(cat "${BRIDGE_VERIFIER_PROMPT:-$root/prompts/verifier.md}")" < "$input" ) > "$out.raw.json"
jq -r '.result' "$out.raw.json" | grep '^{' | tail -1 > "$out.json"
jq -e .findings "$out.json" >/dev/null || { echo "verifier output unparseable: $out.raw.json" >&2; exit 4; }
jq -r '.total_cost_usd' "$out.raw.json"
