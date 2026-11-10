#!/usr/bin/env bash
# Usage: repo-run.sh <run-dir> <model> [case ...]
# post-repo-<m>: one reviewer with read-only git access at the PR head.
# post-repo-<m>+swarm: the same reviewer, after its own pass, checks the post-haiku-7 Sonnet-critic shortlist as hypotheses.
set -euo pipefail
skill="$(cd "$(dirname "$0")/.." && pwd)"
run=$1 model=$2; shift 2
data="${BRIDGE_EVAL_DIR:-$HOME/.claude/bridge-eval}"; repo="${BRIDGE_REPO:-$HOME/Documents/Repo}"
repeats="${BRIDGE_REPEATS:-2}"; short=${model#claude-}; short=${short%%-*}
# BRIDGE_VARIANT names the reviewer variant; BRIDGE_EXTRA_DIR/<case>.md, if present, is appended to its system prompt.
# BRIDGE_NO_MERGE=1 skips the +swarm pass.
base_variant="${BRIDGE_VARIANT:-post-repo-$short}"
rows="$run/rows.tsv"
tools=(--tools "Bash" --allowedTools "Bash(git show:*)" "Bash(git grep:*)" "Bash(git ls-tree:*)")
cases=("$@"); [[ ${#cases[@]} -gt 0 ]] || cases=($(cd "$data/cases" && for c in *; do [[ -f $c/post/input.md ]] && echo "$c"; done; true))

review() { # <system-prompt> <input> <raw-out>
  ( cd "$repo" && timeout 900 claude -p --model "$model" --output-format json --permission-mode dontAsk "${tools[@]}" \
      --max-budget-usd "${BRIDGE_MAX_USD_REVIEWER:-3}" --system-prompt "$(cat "$1")" < "$2" ) > "$3"
}
grade() { # <out-dir> <variant> <cost> <expected-file> <id> <rep>
  local out=$1 variant=$2 cost=$3 ef=$4 id=$5 rep=$6 gc=0
  { echo "EXPECTED:"; cat "$ef"; echo; for a in "$out"/*@*.md; do echo "=== ADVISOR $(basename "$a" .md) ==="; cat "$a"; echo; done; } > "$out/grading-input.md"
  for attempt in 1 2; do
    ( cd "$(mktemp -d)" && timeout 300 claude -p --model claude-sonnet-5-5 --output-format json --tools "" \
        --system-prompt "$(cat "$skill/prompts/grader.md")" < "$out/grading-input.md" ) > "$out/grade.raw.json"
    gc="$(echo "$gc + $(jq -r .total_cost_usd "$out/grade.raw.json")" | bc -l)"
    jq -r .result "$out/grade.raw.json" | grep '^{' | tail -1 > "$out/grade.json"
    jq -e .findings "$out/grade.json" >/dev/null 2>&1 && break
  done
  jq -e .findings "$out/grade.json" >/dev/null 2>&1 || { echo "$id #$rep / $variant: grader unparseable" >&2; return 0; }
  local e h; e=$(grep -c '^- ' "$ef"); h=$(jq '[.findings[]|select(.hit)]|length' "$out/grade.json"); [[ $h -gt $e ]] && h=$e
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$rep" "$variant" "$h" "$e" "$cost" "$gc" "$(jq .noise "$out/grade.json")" >> "$rows"
  echo "$id #$rep / $variant: $h/$e hits, \$$cost" >&2
}
# The graded copy leaves out "Declined to judge": the user sees it collapsed, like the critic's weak list.
findings_only() { jq -r .result "$1" | sed '/^Declined to judge/,$d'; }

for id in "${cases[@]}"; do
  cd_=$data/cases/$id; ef=$cd_/post/expected.md; head=$(tr -dc '0-9a-f' < "$cd_/post/build.txt")
  for rep in $(seq 1 "$repeats"); do
    v1="$base_variant"; o1="$run/$id/$v1/$rep"; mkdir -p "$o1"
    if ! grep -q "^$id	$rep	$v1	" "$rows"; then
      { printf 'Head commit: %s\n\n' "$head"; cat "$cd_/post/input.md"; } > "$o1/input.md"
      cat "$skill/prompts/reviewer-repo.md" > "$o1/system.md"
      [[ -n ${BRIDGE_EXTRA_DIR:-} && -f $BRIDGE_EXTRA_DIR/$id.md ]] && cat "$BRIDGE_EXTRA_DIR/$id.md" >> "$o1/system.md"
      review "$o1/system.md" "$o1/input.md" "$o1/raw.json" || { echo "$id #$rep / $v1: reviewer failed" >&2; continue; }
      findings_only "$o1/raw.json" > "$o1/reviewer@$model@repo.md"
      grade "$o1" "$v1" "$(jq -r .total_cost_usd "$o1/raw.json")" "$ef" "$id" "$rep"
    fi
    [[ ${BRIDGE_NO_MERGE:-} == 1 ]] && continue
    v2="$v1+swarm"; o2="$run/$id/$v2/$rep"; crit="$run/$id/post-haiku-7/$rep/critic/claude-sonnet-5-5"
    grep -q "^$id	$rep	$v2	" "$rows" && continue
    [[ -f $crit.json && -f $o1/raw.json ]] || { echo "$id #$rep / $v2: needs $v1 and the swarm critic" >&2; continue; }
    mkdir -p "$o2"
    { printf 'Head commit: %s\n\n' "$head"; cat "$cd_/post/input.md"; echo; echo "## Your review"; jq -r .result "$o1/raw.json"
      echo; echo "## Swarm shortlist (hypotheses)"; jq -r '.shortlist[] | "- \(.claim)"' "$crit.json"; } > "$o2/input.md"
    review "$skill/prompts/reviewer-merge.md" "$o2/input.md" "$o2/raw.json" || { echo "$id #$rep / $v2: merge failed" >&2; continue; }
    findings_only "$o2/raw.json" > "$o2/reviewer@$model@repo+swarm.md"
    swarm=$(awk -F'\t' -v c="$id" -v r="$rep" '$1==c&&$2==r&&$3=="post-haiku-7"{print $6}' "$rows" | head -1)
    critic=$(jq -r .total_cost_usd "$crit.raw.json")
    cost=$(echo "$(jq -r .total_cost_usd "$o1/raw.json") + $(jq -r .total_cost_usd "$o2/raw.json") + ${swarm:-0} + ${critic:-0}" | bc -l)
    grade "$o2" "$v2" "$cost" "$ef" "$id" "$rep"
  done
done
