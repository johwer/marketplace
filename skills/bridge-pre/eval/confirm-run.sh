#!/usr/bin/env bash
# Usage: confirm-run.sh <run-dir> <variant> [model] [case ...]
# Confirm-only verifier: it cannot drop a finding, so the question is whether "confirmed" points at the right ones.
# Grades the confirmed shortlist alone and compares it with the full advisor set.
set -euo pipefail
skill="$(cd "$(dirname "$0")/.." && pwd)"
run=$1 variant=$2 model=${3:-claude-opus-5-5}; shift $(( $# < 3 ? $# : 3 ))
data="${BRIDGE_EVAL_DIR:-$HOME/.claude/bridge-eval}"
repo="${BRIDGE_REPO:-$HOME/Documents/Repo}"
rep="${BRIDGE_VERIFY_REP:-1}"
rows="$run/confirm-rows.tsv"
[[ -f $rows ]] || printf 'case\tvariant\tverifier\thits_all\texpected\tnoise_all\tclaims\tconfirmed\thits_confirmed\tnoise_confirmed\tverifier_cost\n' > "$rows"
cases=("$@"); [[ ${#cases[@]} -gt 0 ]] || cases=($(ls "$data/cases"))
for id in "${cases[@]}"; do
  case_dir="$data/cases/$id"; repdir="$run/$id/$variant/$rep"; v="$repdir/verify-confirm/$model"
  grep -q "^$id	$variant	$model	" "$rows" && { echo "$id: already done" >&2; continue; }
  vcost=$(BRIDGE_VERIFIER_PROMPT="$skill/prompts/verifier-confirm.md" bash "$skill/bin/verify.sh" "$case_dir/brief.md" "$repdir" "$repo" "$v" "$(cat "$case_dir/base.txt")" "$model") || { echo "$id: verifier failed" >&2; continue; }
  { echo "EXPECTED:"; cat "$case_dir/expected.md"; echo; echo "=== ADVISOR confirmed-shortlist ==="
    jq -r '.findings[] | select(.status=="confirmed") | "- \(.claim)"' "$v.json"; } > "$v.grading-input.md"
  ( cd "$(mktemp -d)" && timeout 300 claude -p --model claude-sonnet-5-5 --output-format json --tools "" \
      --system-prompt "$(cat "$skill/prompts/grader.md")" < "$v.grading-input.md" ) > "$v.grade.raw.json"
  jq -r '.result' "$v.grade.raw.json" | grep '^{' | tail -1 > "$v.grade.json"
  jq -e .findings "$v.grade.json" >/dev/null || { echo "$id: grader unparseable" >&2; continue; }
  expected=$(grep -c '^- ' "$case_dir/expected.md")
  hc=$(jq '[.findings[]|select(.hit)]|length' "$v.grade.json"); [[ $hc -gt $expected ]] && hc=$expected
  read -r ha na < <(awk -F'\t' -v c="$id" -v r="$rep" -v va="$variant" '$1==c&&$2==r&&$3==va{print $4, $8}' "$run/rows.tsv")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$variant" "$model" "$ha" "$expected" "$na" \
    "$(jq '.findings|length' "$v.json")" "$(jq '[.findings[]|select(.status=="confirmed")]|length' "$v.json")" \
    "$hc" "$(jq .noise "$v.grade.json")" "$vcost" >> "$rows"
  echo "$id: all $ha/$expected, confirmed-only $hc/$expected ($(jq '[.findings[]|select(.status=="confirmed")]|length' "$v.json") of $(jq '.findings|length' "$v.json") claims confirmed), \$$vcost" >&2
done
awk -F'\t' 'NR>1{n++; ha+=$4; e+=$5; na+=$6; cl+=$7; co+=$8; hc+=$9; nc+=$10; c+=$11}
  END{if(n) printf "cases %d | all claims: %d, hits %d/%d, noise %d | confirmed: %d claims, hits %d/%d, noise %d | verifier $%.2f ($%.2f per decision)\n", n, cl, ha, e, na, co, hc, e, nc, c, c/n}' "$rows"
