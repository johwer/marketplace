#!/usr/bin/env bash
#
# posthog-create-flag.sh — Create (or update) a standard Repo PostHog feature flag.
#
# DTF helper. Creates a Boolean flag with the team-standard release conditions
# (enabled for the accept + staging hosts at 100%, hidden in prod) — the same
# shape as the `payroll-notes` flag. Idempotent: if the key already exists it
# PATCHes it to the standard config instead of failing.
#
# Usage:
#   posthog-create-flag.sh --key <flag-key> --description "<text>" [options]
#
# Required:
#   --key           Flag key, kebab-case. Convention: include the ticket id,
#                   e.g. nova-2526-service-a-log-notifications
#   --description   Human description. Convention: start with the ticket id,
#                   e.g. "NOVA-2526: Log SMS/email notifications in ServiceA event log"
#
# Options:
#   --hosts h1,h2   Comma-separated $host values to enable for.
#                   Default: polaris-accept.repo.se,leo-stg.terveystalo.com
#   --rollout N     Rollout percentage for the matched group (default 100)
#   --project ID    PostHog project id (default 42565)
#   --api-host URL  PostHog API host (default https://eu.posthog.com)
#   --inactive      Create the flag disabled (default: active)
#   --dry-run       Print the payload, don't call the API
#
# API key resolution (first hit wins):
#   1. $POSTHOG_PERSONAL_API_KEY
#   2. macOS keychain: security find-generic-password -s posthog-personal-api-key -w
#   3. Interactive prompt (offers to store in keychain for reuse)
#
# The key needs the `feature_flag:write` scope. Prefer a SCOPED personal key
# over a full-access one. Create at:
#   <api-host>/settings/user-api-keys
#
set -euo pipefail

KEY="" ; DESC="" ; HOSTS="polaris-accept.repo.se,leo-stg.terveystalo.com"
ROLLOUT=100 ; ACTIVE=true ; DRY_RUN=false

# Project id / API host default from dtf-config.json (posthog section), else built-in.
DTF_CONFIG="$HOME/.claude/dtf-config.json"
PROJECT=42565 ; API_HOST="https://eu.posthog.com"
if [ -f "$DTF_CONFIG" ]; then
  _cfg=$(python3 -c "import json;d=json.load(open('$DTF_CONFIG')).get('posthog',{});print((d.get('projectId') or '42565')+'|'+(d.get('apiHost') or 'https://eu.posthog.com'))" 2>/dev/null || true)
  if [ -n "${_cfg:-}" ]; then PROJECT="${_cfg%%|*}"; API_HOST="${_cfg##*|}"; fi
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --key)         KEY="$2"; shift 2 ;;
    --description) DESC="$2"; shift 2 ;;
    --hosts)       HOSTS="$2"; shift 2 ;;
    --rollout)     ROLLOUT="$2"; shift 2 ;;
    --project)     PROJECT="$2"; shift 2 ;;
    --api-host)    API_HOST="$2"; shift 2 ;;
    --inactive)    ACTIVE=false; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$KEY" ]  || { echo "ERROR: --key is required" >&2; exit 2; }
[ -n "$DESC" ] || { echo "ERROR: --description is required" >&2; exit 2; }

# --- Resolve API key ---
resolve_key() {
  if [ -n "${POSTHOG_PERSONAL_API_KEY:-}" ]; then echo "$POSTHOG_PERSONAL_API_KEY"; return; fi
  if command -v security >/dev/null 2>&1; then
    local k; k=$(security find-generic-password -s posthog-personal-api-key -w 2>/dev/null || true)
    if [ -n "$k" ]; then echo "$k"; return; fi
  fi
  # Interactive prompt
  local k
  read -rs -p "PostHog personal API key (phx_...): " k < /dev/tty; echo >&2
  if command -v security >/dev/null 2>&1 && [ -n "$k" ]; then
    local store; read -r -p "Store this key in macOS keychain for reuse? [y/N] " store < /dev/tty
    if [ "$store" = "y" ] || [ "$store" = "Y" ]; then
      security add-generic-password -U -s posthog-personal-api-key -a "$USER" -w "$k" >/dev/null 2>&1 \
        && echo "Stored in keychain (service: posthog-personal-api-key)." >&2
    fi
  fi
  echo "$k"
}

APIKEY="$(resolve_key)"
[ -n "$APIKEY" ] || { echo "ERROR: no API key provided" >&2; exit 1; }

# --- Build the standard filters payload (single $host property = OR over hosts) ---
HOSTS_JSON=$(printf '%s' "$HOSTS" | python3 -c "import sys,json; print(json.dumps([h for h in sys.stdin.read().split(',') if h]))")
BODY=$(python3 - "$KEY" "$DESC" "$ACTIVE" "$ROLLOUT" "$HOSTS_JSON" <<'PY'
import json, sys
key, desc, active, rollout, hosts_json = sys.argv[1:6]
print(json.dumps({
    "key": key,
    "name": desc,                      # PostHog "name" == the UI Description field
    "active": active == "true",
    "filters": {
        "groups": [{
            "variant": None,
            "properties": [{"key": "$host", "type": "person",
                            "value": json.loads(hosts_json), "operator": "exact"}],
            "rollout_percentage": int(rollout),
            "aggregation_group_type_index": None,
        }],
        "payloads": {},
        "multivariate": None,
    },
}))
PY
)

BASE="$API_HOST/api/projects/$PROJECT/feature_flags"

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN — would POST/PATCH to $BASE/"
  echo "$BODY" | python3 -m json.tool
  exit 0
fi

auth() { curl -s -H "Authorization: Bearer $APIKEY" "$@"; }

# Does the flag already exist?
EXISTING_ID=$(auth "$BASE/?search=$KEY" | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: print(''); sys.exit()
print(next((str(f['id']) for f in d.get('results',[]) if f.get('key')=='$KEY'), ''))
")

if [ -n "$EXISTING_ID" ]; then
  echo "Flag '$KEY' already exists (id $EXISTING_ID) — updating to standard config..."
  RESP=$(auth -X PATCH -H "Content-Type: application/json" -d "$BODY" "$BASE/$EXISTING_ID/")
else
  echo "Creating flag '$KEY'..."
  RESP=$(auth -X POST -H "Content-Type: application/json" -d "$BODY" "$BASE/")
fi

echo "$RESP" | python3 -c "
import sys,json
r=json.load(sys.stdin)
if 'id' in r:
    g=r['filters']['groups'][0]
    print('OK ✓  id=%s key=%s active=%s' % (r['id'], r['key'], r['active']))
    print('     hosts=%s rollout=%s%%' % (g['properties'][0]['value'], g['rollout_percentage']))
    print('     %s/project/%s/feature_flags/%s' % ('$API_HOST', '$PROJECT', r['id']))
else:
    print('ERROR:', json.dumps(r)[:500]); sys.exit(1)
"
