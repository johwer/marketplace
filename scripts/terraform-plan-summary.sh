#!/bin/bash
# terraform-plan-summary.sh — Run terraform plan and present a structured summary
# Used as an automated workflow step for the infra role
set -eo pipefail

# Find the infra directory
INFRA_DIR=""
if [[ -d "infra" ]]; then
  INFRA_DIR="infra"
elif [[ -f "main.tf" ]]; then
  INFRA_DIR="."
else
  # Try to find it relative to monorepo
  MONOREPO=$(jq -r '.paths.monorepo // empty' ~/.claude/dtf-config.json 2>/dev/null)
  if [[ -n "$MONOREPO" && -d "$MONOREPO/infra" ]]; then
    INFRA_DIR="$MONOREPO/infra"
  fi
fi

if [[ -z "$INFRA_DIR" ]]; then
  echo "⚠ No infra/ directory found. Skipping terraform plan."
  exit 0
fi

cd "$INFRA_DIR"

# Ensure terraform is initialized
if [[ ! -d ".terraform" ]]; then
  echo "  Initializing terraform..."
  terraform init -input=false > /dev/null 2>&1 || {
    echo "⚠ terraform init failed — may need credentials or backend config"
    exit 1
  }
fi

# Run plan and capture output
PLAN_OUTPUT=$(terraform plan -detailed-exitcode -no-color 2>&1) || PLAN_EXIT=$?
PLAN_EXIT="${PLAN_EXIT:-0}"

# Parse summary
ADD=$(echo "$PLAN_OUTPUT" | grep -oP '\d+ to add' | grep -oP '\d+' || echo "0")
CHANGE=$(echo "$PLAN_OUTPUT" | grep -oP '\d+ to change' | grep -oP '\d+' || echo "0")
DESTROY=$(echo "$PLAN_OUTPUT" | grep -oP '\d+ to destroy' | grep -oP '\d+' || echo "0")

echo ""
echo "  ┌─────────────────────────────────────┐"
echo "  │        Terraform Plan Summary        │"
echo "  ├─────────────────────────────────────┤"
printf "  │  %-20s %14s │\n" "Resources to add:" "+$ADD"
printf "  │  %-20s %14s │\n" "Resources to change:" "~$CHANGE"
printf "  │  %-20s %14s │\n" "Resources to destroy:" "-$DESTROY"
echo "  └─────────────────────────────────────┘"

# Show resource details
if [[ "$PLAN_EXIT" -eq 2 ]]; then
  echo ""
  echo "  Changes:"
  echo "$PLAN_OUTPUT" | grep -E "^  # |will be created|will be updated|will be destroyed" | head -20 | sed 's/^/    /'

  # DANGER: Warn on destroys
  if [[ "$DESTROY" -gt 0 ]]; then
    echo ""
    echo "  ⚠⚠⚠  WARNING: $DESTROY resource(s) will be DESTROYED  ⚠⚠⚠"
    echo ""
    echo "  Destroyed resources:"
    echo "$PLAN_OUTPUT" | grep "will be destroyed" | sed 's/^/    /'
    echo ""
    echo "  Review carefully before proceeding!"
  fi
elif [[ "$PLAN_EXIT" -eq 0 ]]; then
  echo ""
  echo "  ✓ No changes. Infrastructure is up-to-date."
else
  echo ""
  echo "  ✗ Plan failed. Check output above."
  echo "$PLAN_OUTPUT" | tail -10 | sed 's/^/    /'
  exit 1
fi

echo ""
