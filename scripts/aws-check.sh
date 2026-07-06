#!/usr/bin/env bash
# aws-check.sh — Verify AWS SSO session is active, guide user to login if not.
# Called by /create-stories and /my-dream-team at session start.
# Reads profile name from company-config.json or falls back to "default".

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
CONFIG_FILE="${CLAUDE_DIR}/company-config.json"

# --- Resolve AWS profile name from company config ---
AWS_PROFILE_NAME="default"
if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
  CONFIGURED_PROFILE=$(jq -r '.aws.profileName // empty' "$CONFIG_FILE" 2>/dev/null)
  if [[ -n "$CONFIGURED_PROFILE" ]]; then
    AWS_PROFILE_NAME="$CONFIGURED_PROFILE"
  fi
fi

# --- Resolve SSO start URL for user guidance ---
SSO_URL=""
if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
  SSO_URL=$(jq -r '.aws.ssoStartUrl // empty' "$CONFIG_FILE" 2>/dev/null)
fi

# --- Check if AWS CLI is installed ---
if ! command -v aws &>/dev/null; then
  echo "⚠ AWS CLI not installed. Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  exit 1
fi

# --- Check if ~/.aws/config has the profile ---
if ! grep -q "\[profile ${AWS_PROFILE_NAME}\]" ~/.aws/config 2>/dev/null; then
  echo "⚠ AWS profile '${AWS_PROFILE_NAME}' not found in ~/.aws/config"
  echo ""
  echo "Run the aws-setup skill to configure it:"
  echo "  /aws-setup"
  exit 1
fi

# --- Check if session is active ---
if aws sts get-caller-identity --profile "$AWS_PROFILE_NAME" &>/dev/null; then
  IDENTITY=$(aws sts get-caller-identity --profile "$AWS_PROFILE_NAME" --output text --query 'Arn' 2>/dev/null)
  echo "✓ AWS session active (${AWS_PROFILE_NAME}): ${IDENTITY}"
  exit 0
fi

# --- Session expired — guide user ---
echo "⚠ AWS session expired or not authenticated."
echo "  (Credentials live in ~/.aws — shared across all worktrees, not per-tmux. They just need a refresh.)"
echo ""
# Preferred: refresh via SSO (no secrets to copy) when an sso-session is configured.
if grep -q "\[sso-session ${AWS_PROFILE_NAME}\]" ~/.aws/config 2>/dev/null; then
  echo "Preferred — refresh via SSO (nothing secret to copy):"
  echo "   aws sso login --sso-session ${AWS_PROFILE_NAME}"
  echo "   # then run aws commands with the matching SSO profile, e.g. AWS_PROFILE=${AWS_PROFILE_NAME}-sso <cmd>"
  echo ""
  echo "Fallback (only if SSO login fails) — paste temp creds in YOUR OWN terminal (never into a Claude chat):"
elif [[ -n "$SSO_URL" ]]; then
  echo "Preferred — refresh via SSO:  aws sso login --profile ${AWS_PROFILE_NAME}"
  echo ""
  echo "Fallback (only if SSO login fails) — paste temp creds in YOUR OWN terminal (never into a Claude chat):"
fi
if [[ -n "$SSO_URL" ]]; then
  echo "1. Open ${SSO_URL} → account → role → 'Command line or programmatic access'"
  echo "2. Copy the Access key ID, Secret access key, and Session token"
  echo '3. Run: bash ~/.claude/scripts/aws-set-credentials.sh "<ACCESS_KEY>" "<SECRET_KEY>" "<SESSION_TOKEN>"'
  echo "   (writes ~/.aws/credentials — persists across all terminals and worktrees)"
else
  echo "Run: aws sso login --profile ${AWS_PROFILE_NAME}"
fi
exit 1
