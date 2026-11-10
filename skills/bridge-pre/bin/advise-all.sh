#!/usr/bin/env bash
# Usage: advise-all.sh <brief.md> <variant.conf> <outdir>
# Runs every "<lens> <model> [effort]" line of the variant in parallel; prints per-advisor and total cost.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
brief=$1 variant=$2 outdir=$3
mkdir -p "$outdir"
pids=() names=()
while read -r lens model effort _; do
  [[ -z ${lens:-} || $lens == \#* ]] && continue
  effort=${effort:-medium}
  name="$(basename "$lens" .md)@$model@$effort"
  case " ${names[*]:-} " in *" $name "*) name="$(basename "$lens" .md)-$((${#names[@]}+1))@$model@$effort" ;; esac
  bash "$here/advise.sh" "$brief" "$lens" "$model" "$outdir/$name" "$effort" > "$outdir/$name.cost" 2> "$outdir/$name.err" &
  pids+=($!) names+=("$name")
done < "$variant"
failed=0 total=0
for i in "${!pids[@]}"; do
  if wait "${pids[$i]}"; then
    cost=$(cat "$outdir/${names[$i]}.cost")
    total=$(echo "$total + $cost" | bc -l)
    printf '%-40s $%.4f\n' "${names[$i]}" "$cost"
  else
    failed=1
    printf '%-40s FAILED: %s\n' "${names[$i]}" "$(head -1 "$outdir/${names[$i]}.err")"
  fi
done
printf '%-40s $%.4f\n' "total" "$total"
exit $failed
