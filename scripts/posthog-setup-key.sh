#!/usr/bin/env bash
#
# posthog-setup-key.sh — One-time DTF setup: capture the PostHog personal API key
# and project id so the feature-flag handler works without re-pasting secrets.
#
# Called during `dtf install` / `dtf configure`, or any time via:
#   ~/.claude/scripts/posthog-setup-key.sh
#
# - Stores the API key in the macOS keychain (service: posthog-personal-api-key).
#   The key is NEVER written to disk or to dtf-config.json.
# - Stores the (non-secret) project id + api host in ~/.claude/dtf-config.json
#   under a "posthog" section.
#
# Use a SCOPED personal key (feature_flag:write only), created at:
#   https://eu.posthog.com/settings/user-api-keys
#
set -euo pipefail

CONFIG="$HOME/.claude/dtf-config.json"
KEYCHAIN_SERVICE="posthog-personal-api-key"
DEFAULT_API_HOST="https://eu.posthog.com"

echo "── PostHog feature-flag setup (DTF) ──"

# Skip if already configured (unless --force)
if [ "${1:-}" != "--force" ] \
   && security find-generic-password -s "$KEYCHAIN_SERVICE" -w >/dev/null 2>&1 \
   && [ -f "$CONFIG" ] && python3 -c "import json,sys; sys.exit(0 if json.load(open('$CONFIG')).get('posthog',{}).get('projectId') else 1)" 2>/dev/null; then
  echo "Already configured (key in keychain + projectId in dtf-config.json). Use --force to reconfigure."
  exit 0
fi

read -rs -p "PostHog personal API key (scoped feature_flag:write, phx_...): " APIKEY < /dev/tty; echo
[ -n "$APIKEY" ] || { echo "No key entered — aborting." >&2; exit 1; }

read -r -p "PostHog project id [42565]: " PROJECT < /dev/tty; PROJECT="${PROJECT:-42565}"
read -r -p "PostHog API host [$DEFAULT_API_HOST]: " API_HOST < /dev/tty; API_HOST="${API_HOST:-$DEFAULT_API_HOST}"

# Store the secret in keychain only.
# -A = readable by any app without a GUI prompt, so it works from any terminal /
# headless DTF agent session (not just the process that created it).
security add-generic-password -U -A -s "$KEYCHAIN_SERVICE" -a "$USER" -w "$APIKEY" >/dev/null 2>&1 \
  && echo "✓ API key stored in keychain (service: $KEYCHAIN_SERVICE, readable from any terminal)"

# Store non-secret config in dtf-config.json.
python3 - "$CONFIG" "$PROJECT" "$API_HOST" "$KEYCHAIN_SERVICE" <<'PY'
import json, os, sys
config, project, api_host, svc = sys.argv[1:5]
data = {}
if os.path.exists(config):
    with open(config) as f: data = json.load(f)
data["posthog"] = {
    "projectId": project,
    "apiHost": api_host,
    "keychainService": svc,
    "note": "API key lives in macOS keychain, not here. Use posthog-create-flag.sh to create flags.",
}
with open(config, "w") as f: json.dump(data, f, indent=2)
print("✓ projectId + apiHost written to dtf-config.json (posthog section)")
PY

echo "Done. Create flags with: ~/.claude/scripts/posthog-create-flag.sh --key <ticket-flag> --description \"<TICKET>: ...\""
