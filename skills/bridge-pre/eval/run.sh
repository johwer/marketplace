#!/usr/bin/env bash
# Usage: run.sh <variant> [<variant> ...]
# Replays every case in $BRIDGE_EVAL_DIR/cases (default ~/.claude/bridge-eval/cases) through each variant,
# grades with Sonnet, and prints a per-variant table: hits, cost, hits per dollar, unique hits per advisor.
set -euo pipefail
skill="$(cd "$(dirname "$0")/.." && pwd)"
data="${BRIDGE_EVAL_DIR:-$HOME/.claude/bridge-eval}"
grader_model="${BRIDGE_GRADER_MODEL:-claude-sonnet-5-5}"
repeats="${BRIDGE_REPEATS:-2}"
baseline="${BRIDGE_BASELINE:-sonnet-3lens}"
run="${BRIDGE_RUN_DIR:-$data/results/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$run"
rows="$run/rows.tsv"
[[ -f $rows ]] || printf 'case\trep\tvariant\thits\texpected\tadvisor_cost\tgrader_cost\tnoise\n' > "$rows"

for case_dir in "$data"/cases/*/; do
  id="$(basename "$case_dir")"
  [[ -f $case_dir/brief.md && -f $case_dir/expected.md ]] || { echo "skip $id: needs brief.md and expected.md" >&2; continue; }
  for rep in $(seq 1 "$repeats"); do
  for variant in "$@"; do
    out="$run/$id/$variant/$rep"
    if [[ -f $out/grade.json ]] && jq -e .findings "$out/grade.json" >/dev/null 2>&1 && grep -q "^$id	$rep	$variant	" "$rows"; then
      echo "$id #$rep / $variant: already done" >&2; continue
    fi
    if ls "$out"/*@*.md >/dev/null 2>&1 && ! ls "$out"/*.err 2>/dev/null | xargs grep -l . >/dev/null 2>&1; then
      advisor_cost="$(cat "$out"/*.cost | paste -sd+ - | bc -l)"
    else
      brief_in="$case_dir/brief.md"
      unset BRIDGE_ADVISOR_PROMPT
      if [[ $variant == post-* ]]; then
        [[ -f $case_dir/post/input.md ]] || { echo "skip $id / $variant: no post case" >&2; continue; }
        brief_in="$case_dir/post/input.md"; export BRIDGE_ADVISOR_PROMPT="$skill/prompts/advisor-post.md"
      fi
      if [[ $variant == *-docs ]]; then
        [[ -f $case_dir/base.txt ]] || { echo "skip $id / $variant: no base.txt" >&2; continue; }
        mkdir -p "$out"; brief_in="$out/brief.docs.md"; base_sha=$(cat "$case_dir/base.txt")
        { cat "$case_dir/brief.md"; printf '\n## Team conventions (as written at the time)\n'
          for d in CODING_STYLE_BACKEND API_CONVENTIONS SHARED_LIBRARIES SERVICE_ARCHITECTURE; do
            printf '\n### docs/%s.md\n' "$d"; git -C "${BRIDGE_REPO:-$HOME/Documents/Repo}" show "$base_sha:docs/$d.md" 2>/dev/null || true
          done; } > "$brief_in"
      fi
      if [[ $variant == *-lean ]]; then
        [[ -f $case_dir/lean.txt ]] || { echo "skip $id / $variant: no lean.txt" >&2; continue; }
        mkdir -p "$out"; brief_in="$out/brief.lean.md"
        { cat "$case_dir/brief.md"; printf '\n## Team lean\nThe team currently leans towards option %s.\n' "$(tr -d '[:space:]' < "$case_dir/lean.txt")"; } > "$brief_in"
      fi
      conf="$skill/variants/$variant.conf"
      if [[ $variant == fable-planner ]]; then
        mkdir -p "$out/plan/lenses"
        ( cd "$(mktemp -d)" && timeout 300 claude -p --model claude-fable-5-2 --output-format json --tools "" --max-budget-usd 1 \
            --system-prompt "$(cat "$skill/prompts/planner.md")" < "$brief_in" ) > "$out/plan/raw.json"
        jq -r '.result' "$out/plan/raw.json" | grep '^{' | tail -1 > "$out/plan/plan.json"
        jq -e .advisors "$out/plan/plan.json" >/dev/null || { echo "$id / planner unparseable" >&2; continue; }
        jq -r '.new_lenses // {} | to_entries[] | "\(.key)\t\(.value)"' "$out/plan/plan.json" | while IFS=$'\t' read -r k v; do printf '%s\n' "$v" > "$out/plan/lenses/$k.md"; done
        conf="$out/plan/variant.conf"; : > "$conf"; n=0
        jq -r '.advisors[] | "\(.lens) \(.model)"' "$out/plan/plan.json" | while read -r l m; do
          n=$((n+1)); f="$skill/lenses/$l.md"; [[ -f $out/plan/lenses/$l.md ]] && f="$out/plan/lenses/$l.md"
          [[ -f $f ]] || continue
          cp "$f" "$out/plan/lenses/$(printf '%02d' $n)-$l.md"; echo "$out/plan/lenses/$(printf '%02d' $n)-$l.md $m" >> "$conf"
        done
        plan_cost="$(jq -r .total_cost_usd "$out/plan/raw.json")"
      fi
      advise_log="$(bash "$skill/bin/advise-all.sh" "$brief_in" "$conf" "$out" || true)"
      advisor_cost="$(echo "$advise_log" | awk '$1=="total"{gsub(/\$/,"",$2); print $2}')"
      [[ -n ${plan_cost:-} ]] && advisor_cost="$(echo "$advisor_cost + $plan_cost" | bc -l)" && unset plan_cost
    fi
    {
      expected_file="$case_dir/expected.md"; [[ $variant == post-* && -f $case_dir/post/expected.md ]] && expected_file="$case_dir/post/expected.md"
      echo "EXPECTED:"; cat "$expected_file"; echo
      for answer in "$out"/*@*.md; do echo "=== ADVISOR $(basename "$answer" .md) ==="; cat "$answer"; echo; done
    } > "$out/grading-input.md"
    grader_cost=0
    for attempt in 1 2; do
      ( cd "$(mktemp -d)" && timeout 300 claude -p --model "$grader_model" --output-format json --tools "" \
          --system-prompt "$(cat "$skill/prompts/grader.md")" < "$out/grading-input.md" ) > "$out/grade.raw.json"
      grader_cost="$(echo "$grader_cost + $(jq -r '.total_cost_usd' "$out/grade.raw.json")" | bc -l)"
      jq -r '.result' "$out/grade.raw.json" | grep '^{' | tail -1 > "$out/grade.json"
      jq -e .findings "$out/grade.json" >/dev/null 2>&1 && break
    done
    if ! jq -e .findings "$out/grade.json" >/dev/null 2>&1; then
      echo "$id #$rep / $variant: grader output unparseable, skipped" >&2; continue
    fi
    hits="$(jq '[.findings[] | select(.hit)] | length' "$out/grade.json")"
    expected="$(grep -c '^- ' "$expected_file")"
    [[ $hits -gt $expected ]] && hits=$expected
    noise="$(jq '.noise' "$out/grade.json")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$rep" "$variant" "$hits" "$expected" "$advisor_cost" "$grader_cost" "$noise" >> "$rows"
    echo "$id #$rep / $variant: $hits/$expected hits, \$$advisor_cost" >&2
  done
  done
done

echo
echo "Per variant, mean over $repeats repeat(s); advisor cost only, grading excluded:"
awk -F'\t' -v base="$baseline" -v r="$repeats" 'NR>1{h[$3]+=$4; e[$3]+=$5; c[$3]+=$6; n[$3]+=$8}
  END{printf "%-16s %10s %10s %12s %7s %12s\n","variant","hits","cost USD","hits per $","noise","vs "base;
      for(v in h) printf "%-16s %5.1f/%-4d %10.4f %12.1f %7.1f %+12.1f\n", v, h[v]/r, e[v]/r, c[v]/r, (c[v]>0?h[v]/c[v]:0), n[v]/r, (base in h ? (h[v]-h[base])/r : 0)}' "$rows"
echo "Spread between repeats (a variant whose hits move this much between runs is not yet distinguishable):"
awk -F'\t' 'NR>1{k=$3 FS $2; s[k]+=$4} END{for(k in s){split(k,a,FS); if(!(a[1] in lo)||s[k]<lo[a[1]])lo[a[1]]=s[k]; if(s[k]>hi[a[1]])hi[a[1]]=s[k]} for(v in lo) printf "  %-16s %d..%d hits\n", v, lo[v], hi[v]}' "$rows"
echo
echo "Unique hits (only this advisor found it, within variants of two or more advisors):"
for variant in "$@"; do
  [[ $(grep -cvE '^(#|$)' "$skill/variants/$variant.conf") -gt 1 ]] || continue
  for g in "$run"/*/"$variant"/*/grade.json; do
    jq -r --arg v "$variant" '.findings[] | select(.hit and (.by|length)==1) | "\($v): \(.by[0])"' "$g"
  done
done | sort | uniq -c | sort -rn
echo
echo "Raw: $run"
