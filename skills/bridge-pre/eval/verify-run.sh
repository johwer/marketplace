#!/usr/bin/env bash
# Usage: verify-run.sh <run-dir> <variant> [model] [case ...]
# Runs the verifier over an existing run's advisor answers (no advisor re-run), grades what it keeps
# (confirmed + unverified) against expected.md, and compares with the unverified variant.
set -euo pipefail
skill="$(cd "$(dirname "$0")/.." && pwd)"
run=$1 variant=$2 model=${3:-claude-opus-5-5}; shift $(( $# < 3 ? $# : 3 ))
data="${BRIDGE_EVAL_DIR:-$HOME/.claude/bridge-eval}"
repo="${BRIDGE_REPO:-$HOME/Documents/Repo}"
grader_model="${BRIDGE_GRADER_MODEL:-claude-sonnet-5-5}"
rows="$run/verify-rows.tsv"
[[ -f $rows ]] || printf 'case\trep\tvariant\tverifier\thits_before\thits_kept\texpected\tnoise_before\tnoise_kept\tkept\trefuted\tverifier_cost\tgrader_cost\n' > "$rows"
cases=("$@"); [[ ${#cases[@]} -gt 0 ]] || cases=($(ls "$data/cases"))
for id in "${cases[@]}"; do
  case_dir="$data/cases/$id"
  for repdir in "$run/$id/$variant"/${BRIDGE_VERIFY_REP:-*}/; do
    rep=$(basename "$repdir"); v="$repdir/verify/$model"
    if grep -q "^$id	$rep	$variant	$model	" "$rows"; then echo "$id #$rep: already done" >&2; continue; fi
    vcost=$(bash "$skill/bin/verify.sh" "$case_dir/brief.md" "$repdir" "$repo" "$v" "$(cat "$case_dir/base.txt" 2>/dev/null || true)" "$model") || { echo "$id #$rep: verifier failed" >&2; continue; }
    {
      echo "EXPECTED:"; cat "$case_dir/expected.md"; echo
      echo "=== ADVISOR verified-shortlist ==="
      jq -r '.findings[] | select(.status!="refuted") | "- [\(.status), \(.impact)] \(.claim)"' "$v.json"
    } > "$v.grading-input.md"
    ( cd "$(mktemp -d)" && timeout 300 claude -p --model "$grader_model" --output-format json --tools "" \
        --system-prompt "$(cat "$skill/prompts/grader.md")" < "$v.grading-input.md" ) > "$v.grade.raw.json"
    jq -r '.result' "$v.grade.raw.json" | grep '^{' | tail -1 > "$v.grade.json"
    jq -e .findings "$v.grade.json" >/dev/null || { echo "$id #$rep: grader unparseable" >&2; continue; }
    expected=$(grep -c '^- ' "$case_dir/expected.md")
    kept_hits=$(jq '[.findings[]|select(.hit)]|length' "$v.grade.json"); [[ $kept_hits -gt $expected ]] && kept_hits=$expected
    noise_kept=$(jq .noise "$v.grade.json")
    gcost=$(jq -r .total_cost_usd "$v.grade.raw.json")
    read -r before noise_before < <(awk -F'\t' -v c="$id" -v r="$rep" -v va="$variant" '$1==c&&$2==r&&$3==va{print $4, $8}' "$run/rows.tsv")
    kept=$(jq '[.findings[]|select(.status!="refuted")]|length' "$v.json")
    refuted=$(jq '[.findings[]|select(.status=="refuted")]|length' "$v.json")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$rep" "$variant" "$model" "$before" "$kept_hits" "$expected" "$noise_before" "$noise_kept" "$kept" "$refuted" "$vcost" "$gcost" >> "$rows"
    echo "$id #$rep: hits $before -> $kept_hits / $expected, noise $noise_before -> $noise_kept, kept $kept refuted $refuted, \$$vcost" >&2
  done
done
echo
awk -F'\t' 'NR>1{n++; hb+=$5; hk+=$6; e+=$7; nb+=$8; nk+=$9; k+=$10; r+=$11; c+=$12}
  END{if(n) printf "runs %d  hits %.0f -> %.0f of %d  noise %.0f -> %.0f  kept %d refuted %d  verifier $%.2f ($%.2f per decision)\n", n, hb, hk, e, nb, nk, k, r, c, c/n}' "$rows"
