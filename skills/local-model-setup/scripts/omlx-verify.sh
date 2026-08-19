#!/usr/bin/env bash
# Verify a loaded oMLX model — from a KNOWN-CLEAN machine state.
#
# Why the state check exists: the same 4B model on the same prompt measured 420s at
# 9.25 GB peak with 4.4 GB of swap hot, and 143s at 5.80 GB on a clean machine. A
# 3x error. Timings taken under memory pressure are worthless, so this script refuses
# to benchmark until the machine is quiet (override with --force).
#
#   omlx-verify.sh <MODEL_ID>              state check + throughput + tool calling
#   omlx-verify.sh <MODEL_ID> --full       ... plus a full-size context test (slow)
#   omlx-verify.sh <MODEL_ID> --state      state check only
#   omlx-verify.sh <MODEL_ID> --full --reset   reload the model first to reset Metal pools
#   omlx-verify.sh <MODEL_ID> --force      benchmark anyway on a dirty machine
#
set -uo pipefail

MODEL=${1:-}
[[ -z "$MODEL" || "$MODEL" == -* ]] && { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -12; exit 2; }
shift

FULL=0 RESET=0 FORCE=0 STATE_ONLY=0
for a in "$@"; do
  case "$a" in
    --full) FULL=1 ;; --reset) RESET=1 ;; --force) FORCE=1 ;; --state) STATE_ONLY=1 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

BASE="http://${OMLX_HOST:-127.0.0.1}:${OMLX_PORT:-8000}"
SETTINGS="$HOME/.omlx/settings.json"
KEY=$(python3 -c "
import json
try: print(json.load(open('$SETTINGS'))['auth']['api_key'] or '')
except Exception: print('')
")
[[ -n "$KEY" ]] || { echo "no API key in $SETTINGS" >&2; exit 1; }
COOKIES=$(mktemp -t omlx-vc); trap 'rm -f "$COOKIES" /tmp/omlx-vreq.$$.json' EXIT
curl -s -c "$COOKIES" -X POST "$BASE/admin/api/login" -H 'Content-Type: application/json' \
  -d "{\"api_key\":\"$KEY\"}" >/dev/null

# ---------------------------------------------------------------- state check
echo "== machine state =="
swap_used=$(sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\1/')
containers=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
read -r free_gib compressed_gib <<<"$(vm_stat | awk '
  /Pages free/{f=$3} /occupied by compressor/{c=$5}
  END{printf "%.2f %.2f", f*16384/2**30, c*16384/2**30}')"
printf "  swap used:     %s MB\n  compressed:    %s GiB\n  free:          %s GiB\n  containers up: %s\n" \
  "$swap_used" "$compressed_gib" "$free_gib" "$containers"

# Cumulative `swap used` is history, not pressure — macOS never releases it, so gating
# on it refuses forever on any machine that once swapped. What matters is whether it is
# swapping NOW, so sample the swapout counter over 2s.
so1=$(vm_stat | awk '/Swapouts/{gsub(/\./,"",$2); print $2}')
sleep 2
so2=$(vm_stat | awk '/Swapouts/{gsub(/\./,"",$2); print $2}')
swap_rate=$(( (so2 - so1) / 2 ))
printf "  swapouts/sec:  %s (live pressure indicator)\n" "$swap_rate"

dirty=0
(( swap_rate > 100 )) && { echo "  ! actively swapping ($swap_rate pages/s) — timings will be distorted"; dirty=1; }
awk -v c="$compressed_gib" 'BEGIN{exit !(c+0 > 4)}'  && { echo "  ! compressor > 4 GiB — memory is tight"; dirty=1; }
[[ "$containers" != "0" ]] && { echo "  ! Docker containers running — stop them first"; dirty=1; }
awk -v s="$swap_used" 'BEGIN{exit !(s+0 > 1024)}' && \
  echo "  note: ${swap_used} MB swap used historically — fine if swapouts/sec is ~0"
[[ $dirty -eq 0 ]] && echo "  state: CLEAN — safe to benchmark"

if [[ $dirty -eq 1 && $FORCE -eq 0 ]]; then
  cat >&2 <<EOF

REFUSING to benchmark: the machine is under memory pressure, and any number measured
now is unreliable (measured 3x error from exactly this). Fix, then re-run:
  - stop Docker containers
  - scripts/omlx-down.sh --models to unload, wait for swapouts/sec to fall, then reload
  - or pass --force to measure anyway and label the result as unreliable
EOF
  exit 3
fi
[[ $STATE_ONLY -eq 1 ]] && exit 0

if [[ $RESET -eq 1 ]]; then
  echo "== resetting model (clears pooled Metal buffers) =="
  curl -s -b "$COOKIES" -X POST "$BASE/admin/api/models/$MODEL/unload" >/dev/null
  curl -s -b "$COOKIES" -X POST "$BASE/admin/api/models/$MODEL/load" --max-time 900 >/dev/null
  echo "  reloaded"
fi

# The configured window lives in ~/.omlx/model_settings.json — /admin/api/models only
# exposes `model_context_length`, the model's NATIVE max (262144 for Qwen3.5), which is
# useless here and would size the test to the wrong thing entirely.
ctx_window=$(python3 -c "
import json
try:
    d=json.load(open('$HOME/.omlx/model_settings.json'))['models']
    print(d.get('$MODEL',{}).get('max_context_window') or 0)
except Exception: print(0)
")
if [[ "${ctx_window:-0}" == "0" ]]; then
  echo "  ! no max_context_window configured for $MODEL — set one before testing context" >&2
  [[ $FULL -eq 1 ]] && exit 4
fi
echo "== model: $MODEL (configured context: ${ctx_window:-?}) =="

ask() {  # prompt -> tok/s
  curl -s --max-time 600 "$BASE/v1/chat/completions" -H 'Content-Type: application/json' \
   -H "Authorization: Bearer $KEY" \
   -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$1\"}],\"max_tokens\":250,\"temperature\":0}" \
   | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: print('  no response'); raise SystemExit
u=d.get('usage',{}); t=u.get('total_time') or 0; n=u.get('completion_tokens') or 0
print(f'  {n} tok in {t:.2f}s = {n/t if t else 0:.1f} tok/s')"
}

echo "== 1. throughput =="
ask "Say hi." >/dev/null
ask "Explain what a debounce function does in two sentences."
ask "List five TypeScript utility types."

# Loose phrasing on purpose. A coaxed prompt ("use the X tool") passes even on models
# that will not pick a tool unprompted, which is the failure that actually breaks
# agentic loops — the 4B refused this exact wording while the 9B complied.
echo "== 2. tool calling (loose phrasing — do NOT coax) =="
curl -s --max-time 300 "$BASE/v1/messages" -H "x-api-key: $KEY" \
 -H 'anthropic-version: 2023-06-01' -H 'Content-Type: application/json' \
 -d "{\"model\":\"$MODEL\",\"max_tokens\":300,\"tools\":[{\"name\":\"read_file\",\"description\":\"Read a file from disk\",\"input_schema\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}}],\"messages\":[{\"role\":\"user\",\"content\":\"Read the file /etc/hosts using the available tool.\"}]}" \
 | python3 -c "
import sys,json
d=json.load(sys.stdin)
types=[b.get('type') for b in d.get('content',[])]
ok = d.get('stop_reason')=='tool_use' and 'tool_use' in types
print('  stop_reason:', d.get('stop_reason'), '| blocks:', types)
print('  PASS — picks a tool unprompted' if ok else
      '  WEAK — did not call the tool unprompted; agentic loops will stall or need coaxing')
for b in d.get('content',[]):
    if b.get('type')=='text': print('   said:', repr(b.get('text','')[:120]))"

if [[ $FULL -eq 1 ]]; then
  # ~98% of the configured window: you cannot send more than max_context_window, so
  # this is the strongest possible proof that the configured context actually works.
  target=$(( ctx_window * 98 / 100 ))
  reps=$(( target / 18 ))   # ~18.01 tokens per filler repetition, measured
  echo "== 3. full-size context (~${target} tok, this blocks the server) =="
  python3 -c "
import json
filler=('The quick brown fox jumps over the lazy dog. Local inference needs a company id. ')*$reps
print(json.dumps({'model':'$MODEL','max_tokens':20,'temperature':0,
 'messages':[{'role':'user','content':filler+'\nReply with the single word: done'}]}))
" > /tmp/omlx-vreq.$$.json
  start=$(date +%s)
  curl -s --max-time 2400 "$BASE/v1/chat/completions" -H 'Content-Type: application/json' \
   -H "Authorization: Bearer $KEY" -d @/tmp/omlx-vreq.$$.json | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: print('  NO RESPONSE (timeout)'); raise SystemExit
u=d.get('usage',{}); e=d.get('error')
if e: print('  FAIL —', str(e.get('message'))[:220])
else: print('  PASS — prompt_tokens=%s in %.1fs (%.0f tok/s prefill), reply %r'%(
    u.get('prompt_tokens'), u.get('total_time') or 0,
    (u.get('prompt_tokens') or 0)/(u.get('total_time') or 1),
    d['choices'][0]['message']['content'][:30]))"
  echo "  wall: $(( $(date +%s) - start ))s"
  echo "  peak/throttle:"
  grep -E "throttl|Reclaimed" "$HOME/.omlx/logs/server.log" | tail -2 | sed 's/^/    /' | cut -c1-150
fi

echo
echo "Record any figure together with the state block above — a number without its"
echo "machine state is not a measurement."
