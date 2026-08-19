#!/usr/bin/env bash
# Tear down or auto-expire the local oMLX model server.
#
# A loaded model holds 3-6 GiB resident indefinitely — oMLX ships with idle unload
# DISABLED (idle_timeout_seconds: null), so nothing reclaims it on its own. This
# script covers both the hard stop and arming the built-in self-cleaner.
#
#   omlx-down.sh              unload models, stop the service, confirm the port is free
#   omlx-down.sh --models     unload models only, leave the server running
#   omlx-down.sh --idle 900   arm auto-unload after 900s idle, then exit (server stays up)
#   omlx-down.sh --status     what's loaded, what it costs, whether idle unload is armed
#   omlx-down.sh --disable    also stop the service starting again at login
#
set -uo pipefail

HOST=${OMLX_HOST:-127.0.0.1}
PORT=${OMLX_PORT:-8000}
BASE="http://$HOST:$PORT"
SETTINGS="$HOME/.omlx/settings.json"
COOKIES=$(mktemp -t omlx-cookies)
trap 'rm -f "$COOKIES"' EXIT

up() { curl -sf --max-time 5 "$BASE/health" >/dev/null 2>&1; }

api_key() {
  [[ -f "$SETTINGS" ]] || return 1
  python3 -c "
import json,sys
try: print(json.load(open('$SETTINGS'))['auth']['api_key'] or '')
except Exception: print('')
" 2>/dev/null
}

login() {
  local key; key=$(api_key)
  [[ -n "$key" ]] || { echo "  ! no API key in $SETTINGS — cannot reach the admin API" >&2; return 1; }
  curl -s -c "$COOKIES" -X POST "$BASE/admin/api/login" \
    -H 'Content-Type: application/json' -d "{\"api_key\":\"$key\"}" >/dev/null 2>&1
  grep -q . "$COOKIES" 2>/dev/null
}

loaded_models() {
  curl -s -b "$COOKIES" "$BASE/admin/api/models" 2>/dev/null | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for m in d.get('models',[]):
    if m.get('is_loaded') or m.get('loaded'): print(m['id'])
" 2>/dev/null
}

show_status() {
  if ! up; then echo "server:  not running"; return; fi
  curl -s "$BASE/health" | python3 -c "
import sys,json
d=json.load(sys.stdin); e=d.get('engine_pool',{})
print('server:  running on $BASE')
print('default:', d.get('default_model') or '(none)')
print('loaded:  %d model(s), %.2f GiB resident, ceiling %.2f GiB'%(
    e.get('loaded_count',0), e.get('current_model_memory',0)/2**30, e.get('final_ceiling',0)/2**30))
"
  python3 -c "
import json
try:
    t=json.load(open('$SETTINGS')).get('idle_timeout',{}).get('idle_timeout_seconds')
except Exception: t=None
print('idle unload:', f'armed at {t}s ({t//60} min)' if t else 'DISABLED — a loaded model holds RAM forever')
"
}

unload_all() {
  up || { echo "  server not running, nothing to unload"; return 0; }
  login || return 1
  local any=0
  while read -r m; do
    [[ -z "$m" ]] && continue
    any=1
    printf '  unloading %s ... ' "$m"
    curl -s -b "$COOKIES" -X POST "$BASE/admin/api/models/$m/unload" >/dev/null && echo ok || echo FAILED
  done < <(loaded_models)
  [[ $any -eq 0 ]] && echo "  no models loaded"
  return 0
}

arm_idle() {
  local secs=$1
  (( secs >= 60 )) || { echo "  ! idle timeout must be >= 60s (oMLX minimum)" >&2; return 1; }
  up || { echo "  ! server not running — start it before arming idle unload" >&2; return 1; }
  login || return 1
  curl -s -b "$COOKIES" -X POST "$BASE/admin/api/global-settings" \
    -H 'Content-Type: application/json' -d "{\"idle_timeout_seconds\":$secs}" >/dev/null
  python3 -c "
import json
t=json.load(open('$SETTINGS')).get('idle_timeout',{}).get('idle_timeout_seconds')
print(f'  idle unload armed: models drop after {t}s ({t//60} min) idle' if t==$secs
      else f'  ! verification failed, settings.json reads {t}')
"
}

case "${1:-}" in
  --status) show_status; exit 0 ;;
  --models) echo "Unloading models (server stays up)..."; unload_all; echo; show_status; exit 0 ;;
  --idle)
    secs=${2:-900}
    echo "Arming oMLX idle self-cleaner..."; arm_idle "$secs"; exit $? ;;
esac

echo "Shutting down oMLX..."
unload_all

echo "  stopping brew service ... "
if brew services list 2>/dev/null | grep -q '^omlx'; then
  brew services stop jundot/omlx/omlx >/dev/null 2>&1 && echo "  service stopped" || echo "  ! brew services stop failed"
else
  echo "  (not registered with brew services)"
fi

# `omlx stop` also covers a foreground `omlx serve` or the menu-bar app
command -v omlx >/dev/null && omlx stop >/dev/null 2>&1

if [[ "${1:-}" == "--disable" ]]; then
  brew services list 2>/dev/null | grep -q '^omlx' \
    && { brew services stop jundot/omlx/omlx >/dev/null 2>&1; echo "  login autostart disabled"; }
fi

# Confirm rather than assume — a stop that silently failed is the failure mode here.
sleep 2
if up; then
  echo "  ! server still answering on $BASE — check: brew services list | grep omlx"
  exit 1
fi
echo "  port $PORT free — oMLX is down, RAM released"
