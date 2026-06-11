#!/usr/bin/env bash
#
# posthog-delete-flag.sh — Delete (or restore) a Repo PostHog feature flag.
#
# DTF helper. Soft-deletes a feature flag the same way the PostHog UI does
# (PATCH deleted:true) — the flag disappears from the active list but can be
# restored. Companion to posthog-create-flag.sh.
#
# Use this to retire a flag AFTER the last code reference is merged out, so the
# PostHog project doesn't accumulate dead flags.
#
# Usage:
#   posthog-delete-flag.sh --key nova-2526-service-a-log-notifications
#   posthog-delete-flag.sh --ticket NOVA-2831 --key "Legacy user redirect"   # derives nova-2831-legacy-user-redirect
#   posthog-delete-flag.sh --id 196664                                       # delete by numeric id (skips search)
#   posthog-delete-flag.sh --key nova-2526-... --restore                     # un-delete
#   posthog-delete-flag.sh --key nova-2526-... --dry-run                     # show match, change nothing
#
# Key/identity (one required):
#   --key           Full kebab-case key, OR (with --ticket) the slug portion.
#   --ticket        Ticket id (e.g. NOVA-2831). Builds/prefixes the key as
#                   <ticket-lowercased>-<kebab-slug>, mirroring posthog-create-flag.sh.
#   --id            Numeric PostHog flag id. Bypasses the key search entirely.
#
# Options:
#   --restore       Un-delete instead of delete (PATCH deleted:false).
#   --yes           Skip the confirmation prompt (required in non-interactive runs).
#   --project ID    PostHog project id (default from dtf-config.json, else 42565).
#   --api-host URL  PostHog API host (default from dtf-config.json, else https://eu.posthog.com).
#   --dry-run       Print the matched flag and intended action, don't call the API.
#
# API key resolution (first hit wins):
#   1. $POSTHOG_PERSONAL_API_KEY
#   2. macOS keychain: security find-generic-password -s posthog-personal-api-key -w
#   3. Interactive prompt (offers to store in keychain for reuse)
#
# The key needs the `feature_flag:write` scope. Create at:
#   <api-host>/settings/user-api-keys
#
set -euo pipefail

KEY="" ; TICKET="" ; FLAG_ID="" ; ACTION="delete" ; ASSUME_YES=false ; DRY_RUN=false

# Project id / API host default from dtf-config.json (posthog section), else built-in.
DTF_CONFIG="$HOME/.claude/dtf-config.json"
PROJECT=42565 ; API_HOST="https://eu.posthog.com"
if [ -f "$DTF_CONFIG" ]; then
  _cfg=$(python3 -c "import json;d=json.load(open('$DTF_CONFIG')).get('posthog',{});print((d.get('projectId') or '42565')+'|'+(d.get('apiHost') or 'https://eu.posthog.com'))" 2>/dev/null || true)
  if [ -n "${_cfg:-}" ]; then PROJECT="${_cfg%%|*}"; API_HOST="${_cfg##*|}"; fi
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --key)       KEY="$2"; shift 2 ;;
    --ticket)    TICKET="$2"; shift 2 ;;
    --id)        FLAG_ID="$2"; shift 2 ;;
    --restore)   ACTION="restore"; shift ;;
    --yes|-y)    ASSUME_YES=true; shift ;;
    --project)   PROJECT="$2"; shift 2 ;;
    --api-host)  API_HOST="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    -h|--help)   sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- Derive the flag key in the standard shape: <ticket-lowercased>-<kebab-slug> ---
# (same logic as posthog-create-flag.sh, so the two stay in lockstep)
slugify() { python3 -c "import re,sys; s=re.sub(r'[^a-z0-9]+','-',sys.argv[1].lower()).strip('-'); print(re.sub(r'-+','-',s))" "$1"; }

if [ -n "$TICKET" ]; then
  TICKET_LC=$(printf '%s' "$TICKET" | tr '[:upper:]' '[:lower:]')
  SLUG=$(slugify "${KEY:-}")
  case "$SLUG" in
    "$TICKET_LC"-*) KEY="$SLUG" ;;
    "") KEY="$TICKET_LC" ;;
    *)  KEY="${TICKET_LC}-${SLUG}" ;;
  esac
fi

[ -n "$KEY" ] || [ -n "$FLAG_ID" ] || { echo "ERROR: provide --key, --ticket (+ slug), or --id" >&2; exit 2; }

# --- Resolve API key (env > keychain > interactive prompt) ---
resolve_key() {
  if [ -n "${POSTHOG_PERSONAL_API_KEY:-}" ]; then
    echo "→ using PostHog key from \$POSTHOG_PERSONAL_API_KEY env var" >&2
    echo "$POSTHOG_PERSONAL_API_KEY"; return
  fi
  if command -v security >/dev/null 2>&1; then
    local k; k=$(security find-generic-password -s posthog-personal-api-key -w 2>/dev/null || true)
    if [ -n "$k" ]; then
      echo "→ using PostHog key from macOS keychain (service: posthog-personal-api-key)" >&2
      echo "$k"; return
    fi
  fi
  if [ ! -r /dev/tty ]; then
    echo "ERROR: no PostHog key in \$POSTHOG_PERSONAL_API_KEY or keychain (service: posthog-personal-api-key), and no TTY to prompt." >&2
    echo "       Fix: run ~/.claude/scripts/posthog-setup-key.sh once, or export POSTHOG_PERSONAL_API_KEY." >&2
    exit 1
  fi
  echo "→ no key in env or keychain — prompting (run posthog-setup-key.sh to store it for reuse)" >&2
  local k; read -rs -p "PostHog personal API key (phx_...): " k < /dev/tty; echo >&2
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

BASE="$API_HOST/api/projects/$PROJECT/feature_flags"
auth() { curl -s -H "Authorization: Bearer $APIKEY" "$@"; }

# --- Resolve the flag: by --id, else exact-key match from search (guarded) ---
if [ -z "$FLAG_ID" ]; then
  FOUND=$(auth "$BASE/?search=$KEY" | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: print('ERR|could not parse PostHog response'); sys.exit()
res=d.get('results', d if isinstance(d,list) else [])
exact=[f for f in res if f.get('key')=='$KEY']
if len(exact)==0: print('NONE|no flag with key \'$KEY\' (searched %d)'%len(res))
elif len(exact)>1: print('MANY|%d flags share key \'$KEY\' — pass --id'%len(exact))
else:
    f=exact[0]
    print('OK|%s|%s|%s|%s|%s'%(f['id'], f.get('key'), f.get('active'), f.get('deleted'), (f.get('name') or '').replace('|','/')))
")
  STATUS="${FOUND%%|*}"; REST="${FOUND#*|}"
  if [ "$STATUS" != "OK" ]; then echo "ERROR: $REST" >&2; exit 1; fi
  FLAG_ID="${REST%%|*}"; META="${REST#*|}"
  F_KEY="${META%%|*}"; META="${META#*|}"
  F_ACTIVE="${META%%|*}"; META="${META#*|}"
  F_DELETED="${META%%|*}"; F_NAME="${META#*|}"
else
  # Fetch the single flag by id to show its current state.
  read -r F_KEY F_ACTIVE F_DELETED F_NAME < <(auth "$BASE/$FLAG_ID/" | python3 -c "
import sys,json
f=json.load(sys.stdin)
if 'id' not in f: print('? ? ? (not found)'); sys.exit()
print('%s %s %s %s'%(f.get('key'),f.get('active'),f.get('deleted'),(f.get('name') or '').replace(' ','_')))
")
fi

echo "Matched flag:"
echo "  id=$FLAG_ID  key=$F_KEY  active=$F_ACTIVE  deleted=$F_DELETED"
echo "  name=$F_NAME"
echo "  $API_HOST/project/$PROJECT/feature_flags/$FLAG_ID"

# --- No-op guards ---
if [ "$ACTION" = "delete" ] && [ "$F_DELETED" = "True" ]; then
  echo "Already deleted — nothing to do. (Use --restore to un-delete.)"; exit 0
fi
if [ "$ACTION" = "restore" ] && [ "$F_DELETED" = "False" ]; then
  echo "Already active (not deleted) — nothing to restore."; exit 0
fi

if [ "$ACTION" = "restore" ]; then PATCH='{"deleted": false}'; VERB="Restore"; else PATCH='{"deleted": true}'; VERB="Delete"; fi

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN — would PATCH $BASE/$FLAG_ID/ with $PATCH ($VERB)"; exit 0
fi

# --- Confirm (destructive). Skip with --yes; require --yes when non-interactive. ---
if [ "$ASSUME_YES" != true ]; then
  if [ ! -r /dev/tty ]; then
    echo "ERROR: refusing to $VERB without confirmation in a non-interactive run. Re-run with --yes." >&2; exit 1
  fi
  read -r -p "$VERB this flag? [y/N] " ans < /dev/tty
  case "$ans" in y|Y) ;; *) echo "Aborted."; exit 0 ;; esac
fi

RESP=$(auth -X PATCH -H "Content-Type: application/json" -d "$PATCH" "$BASE/$FLAG_ID/")
echo "$RESP" | python3 -c "
import sys,json
r=json.load(sys.stdin)
if 'id' in r:
    print('OK ✓  id=%s key=%s deleted=%s active=%s' % (r['id'], r['key'], r.get('deleted'), r.get('active')))
    if r.get('deleted'): print('     Restore with: posthog-delete-flag.sh --id %s --restore' % r['id'])
else:
    print('ERROR:', json.dumps(r)[:500]); sys.exit(1)
"
