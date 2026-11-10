#!/usr/bin/env bash
# Usage: critic-run.sh <run-dir> <variant> [model] [case ...]
# A critic without code access ranks an existing run's advisor answers. Grades its shortlist alone against expected.md.
set -euo pipefail
skill="$(cd "$(dirname "$0")/.." && pwd)"
run=$1 variant=$2 model=${3:-claude-opus-5-5}; shift $(( $# < 3 ? $# : 3 ))
data="${BRIDGE_EVAL_DIR:-$HOME/.claude/bridge-eval}"
rows="$run/critic-rows.tsv"
[[ -f $rows ]] || printf 'case\trep\tvariant\tcritic\thits_all\texpected\tnoise_all\tshortlist\tweak\thits_short\tnoise_short\tcritic_cost\n' > "$rows"
cases=("$@"); [[ ${#cases[@]} -gt 0 ]] || cases=($(ls "$data/cases"))
for id in "${cases[@]}"; do
  case_dir="$data/cases/$id"
  expected_file="$case_dir/expected.md"; [[ $variant == post-* && -f $case_dir/post/expected.md ]] && expected_file="$case_dir/post/expected.md"
  brief="$case_dir/brief.md"; [[ $variant == post-* ]] && brief="$case_dir/post/input.md"
  for repdir in "$run/$id/$variant"/*/; do
    [[ -d $repdir ]] || continue
    rep=$(basename "$repdir"); c="$repdir/critic/$model"; mkdir -p "$(dirname "$c")"
    grep -q "^$id	$rep	$variant	$model	" "$rows" && { echo "$id #$rep: already done" >&2; continue; }
    { echo "=== BRIEF ==="; cat "$brief"; echo
      for a in "$repdir"/*@*@*.md; do echo "=== ADVISOR $(basename "$a" .md) ==="; cat "$a"; echo; done; } > "$c.input.md"
    [[ $(wc -c < "$c.input.md") -lt 800000 ]] || { echo "$id #$rep: critic input too large" >&2; continue; }
    ( cd "$(mktemp -d)" && timeout 300 claude -p --model "$model" --output-format json --tools "" --max-budget-usd 1 \
        --system-prompt "$(cat "$skill/prompts/critic.md")" < "$c.input.md" ) > "$c.raw.json" || { echo "$id #$rep: critic failed" >&2; continue; }
    jq -r '.result' "$c.raw.json" | grep '^{' | tail -1 > "$c.json"
    jq -e .shortlist "$c.json" >/dev/null 2>&1 || { echo "$id #$rep: critic unparseable" >&2; continue; }
    { echo "EXPECTED:"; cat "$expected_file"; echo; echo "=== ADVISOR critic-shortlist ==="
      jq -r '.shortlist[] | "- \(.claim)"' "$c.json"; } > "$c.grading-input.md"
    ( cd "$(mktemp -d)" && timeout 300 claude -p --model claude-sonnet-5-5 --output-format json --tools "" \
        --system-prompt "$(cat "$skill/prompts/grader.md")" < "$c.grading-input.md" ) > "$c.grade.raw.json"
    jq -r '.result' "$c.grade.raw.json" | grep '^{' | tail -1 > "$c.grade.json"
    jq -e .findings "$c.grade.json" >/dev/null 2>&1 || { echo "$id #$rep: grader unparseable" >&2; continue; }
    expected=$(grep -c '^- ' "$expected_file")
    hs=$(jq '[.findings[]|select(.hit)]|length' "$c.grade.json"); [[ $hs -gt $expected ]] && hs=$expected
    read -r ha na < <(awk -F'\t' -v c="$id" -v r="$rep" -v va="$variant" '$1==c&&$2==r&&$3==va{print $4, $8}' "$run/rows.tsv")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$rep" "$variant" "$model" "$ha" "$expected" "$na" \
      "$(jq '.shortlist|length' "$c.json")" "$(jq '.weak|length' "$c.json")" "$hs" "$(jq .noise "$c.grade.json")" "$(jq -r .total_cost_usd "$c.raw.json")" >> "$rows"
    echo "$id #$rep: all $ha/$expected -> shortlist $hs/$expected" >&2
  done
done
awk -F'\t' -v v="$variant" '$3==v{n++; ha+=$5; e+=$6; na+=$7; s+=$8; w+=$9; hs+=$10; ns+=$11; c+=$12}
  END{if(n) printf "%s: runs %d | all: hits %d/%d noise %d | shortlist (%d points, %d weak): hits %d/%d noise %d | critic $%.2f ($%.3f per decision)\n", v, n, ha, e, na, s, w, hs, e, ns, c, c/n}' "$rows"
