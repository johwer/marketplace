#!/usr/bin/env bash
# Usage: lean-report.sh <run-dir> [blind-variant] [lean-variant]
# Compares a blind variant with its -lean twin: how often advisors recommend the lean option,
# and hits, split by whether the lean was right (the case's expected.md says "Recommend option <lean>")
# or wrong (review changed the first build). Right-lean cases: those listed in $RIGHT_LEAN.
set -euo pipefail
run=$1 blind=${2:-sonnet-3lens} lean=${3:-sonnet-3lens-lean}
cases="${BRIDGE_EVAL_DIR:-$HOME/.claude/bridge-eval}/cases"
right_lean="${RIGHT_LEAN:-clean-4597 clean-4702 proj-3847 proj-4061}"
printf '%-14s %-6s %-20s %10s %8s\n' case lean variant "agree/adv" hits
for case_dir in "$cases"/*/; do
  id=$(basename "$case_dir"); [[ -f $case_dir/lean.txt ]] || continue
  letter=$(tr -d '[:space:]' < "$case_dir/lean.txt")
  kind=wrong; [[ " $right_lean " == *" $id "* ]] && kind=right
  for v in "$blind" "$lean"; do
    agree=0 total=0
    for a in "$run/$id/$v"/*/*@*.md; do
      [[ -f $a ]] || continue
      total=$((total+1))
      grep -qiE "^\**Recommendation:?\**:? *\**(option )?$letter\b" "$a" && agree=$((agree+1))
    done
    hits=$(awk -F'\t' -v c="$id" -v v="$v" '$1==c && $3==v {h+=$4; n++} END{printf "%.1f", n?h/n:0}' "$run/rows.tsv")
    printf '%-14s %-6s %-20s %6d/%-3d %8s\n' "$id" "$kind" "$v" "$agree" "$total" "$hits"
  done
done
