#!/usr/bin/env bash
# aws-set-credentials.sh — Write temporary AWS credentials to ~/.aws/credentials
# Persists across all terminals and worktrees (lives in home directory).
# Reads profile name from company-config.json.
#
# Usage:
#   bash ~/.claude/scripts/aws-set-credentials.sh <ACCESS_KEY_ID> <SECRET_ACCESS_KEY> <SESSION_TOKEN>
#
# Or pipe the 3 export lines from the AWS SSO portal:
#   bash ~/.claude/scripts/aws-set-credentials.sh --from-exports
#   (then paste the 3 export lines and press Ctrl+D)

set -euo pipefail

CLAUDE_DIR="${HOME}/.claude"
CONFIG_FILE="${CLAUDE_DIR}/company-config.json"
CREDENTIALS_FILE="${HOME}/.aws/credentials"

# --- Resolve AWS profile name ---
AWS_PROFILE_NAME="default"
if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
  CONFIGURED_PROFILE=$(jq -r '.aws.profileName // empty' "$CONFIG_FILE" 2>/dev/null)
  if [[ -n "$CONFIGURED_PROFILE" ]]; then
    AWS_PROFILE_NAME="$CONFIGURED_PROFILE"
  fi
fi

# --- Parse arguments ---
if [[ "${1:-}" == "--from-exports" ]]; then
  echo "Paste the 3 export lines from the AWS SSO portal, then press Ctrl+D:"
  INPUT=$(cat)
  ACCESS_KEY=$(echo "$INPUT" | grep -oP 'AWS_ACCESS_KEY_ID="?\K[^"]+' || echo "$INPUT" | grep AWS_ACCESS_KEY_ID | sed 's/.*="\?\([^"]*\)"\?/\1/')
  SECRET_KEY=$(echo "$INPUT" | grep -oP 'AWS_SECRET_ACCESS_KEY="?\K[^"]+' || echo "$INPUT" | grep AWS_SECRET_ACCESS_KEY | sed 's/.*="\?\([^"]*\)"\?/\1/')
  SESSION_TOKEN=$(echo "$INPUT" | grep -oP 'AWS_SESSION_TOKEN="?\K[^"]+' || echo "$INPUT" | grep AWS_SESSION_TOKEN | sed 's/.*="\?\([^"]*\)"\?/\1/')
elif [[ $# -eq 3 ]]; then
  ACCESS_KEY="$1"
  SECRET_KEY="$2"
  SESSION_TOKEN="$3"
else
  echo "Usage:"
  echo "  bash $0 <ACCESS_KEY_ID> <SECRET_ACCESS_KEY> <SESSION_TOKEN>"
  echo "  bash $0 --from-exports  (then paste export lines)"
  exit 1
fi

# --- Validate ---
if [[ -z "$ACCESS_KEY" || -z "$SECRET_KEY" || -z "$SESSION_TOKEN" ]]; then
  echo "✗ Could not parse all three credential values."
  exit 1
fi

# --- Ensure ~/.aws/ exists ---
mkdir -p "$(dirname "$CREDENTIALS_FILE")"

# --- Write or update credentials file ---
# Remove existing profile section if present, then append new one
if [[ -f "$CREDENTIALS_FILE" ]]; then
  # Remove old profile block (from [profile] to next [profile] or EOF)
  python3 -c "
import re, sys
content = open('$CREDENTIALS_FILE').read()
# Remove the profile section including trailing newlines
pattern = r'\[${AWS_PROFILE_NAME}\][^\[]*'
content = re.sub(pattern, '', content).strip()
if content:
    content += '\n\n'
open('$CREDENTIALS_FILE', 'w').write(content)
" 2>/dev/null || true
fi

# Append new credentials
cat >> "$CREDENTIALS_FILE" << EOF
[${AWS_PROFILE_NAME}]
aws_access_key_id=${ACCESS_KEY}
aws_secret_access_key=${SECRET_KEY}
aws_session_token=${SESSION_TOKEN}
EOF

# --- Verify ---
if aws sts get-caller-identity --profile "$AWS_PROFILE_NAME" &>/dev/null; then
  IDENTITY=$(aws sts get-caller-identity --profile "$AWS_PROFILE_NAME" --output text --query 'Arn' 2>/dev/null)
  echo "✓ Credentials saved to ~/.aws/credentials [${AWS_PROFILE_NAME}]"
  echo "✓ Session active: ${IDENTITY}"
  echo ""
  echo "These credentials persist across all terminals and worktrees."
  echo "They expire after ~8 hours — re-run this script when needed."
else
  echo "✗ Credentials saved but verification failed. Check if the values are correct."
  exit 1
fi
