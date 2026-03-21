#!/bin/bash
# verify-infra-workflows.sh — Verify GitHub Actions workflows exist for infra changes
# Used as an automated workflow step for the infra role
set -eo pipefail

# Find repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
ISSUES=0

echo ""
echo "  Checking GitHub Actions workflows for infra..."
echo ""

# Check for terraform plan workflow
PLAN_WF=$(find "$WORKFLOWS_DIR" -name "*.yml" -exec grep -l "terraform.*plan\|terraform_plan\|tf-plan\|infra.*plan" {} \; 2>/dev/null | head -1)
if [[ -n "$PLAN_WF" ]]; then
  echo "  ✓ Plan workflow: $(basename "$PLAN_WF")"

  # Check if it triggers on infra/ changes
  if grep -q "infra/" "$PLAN_WF" 2>/dev/null; then
    echo "    ✓ Triggers on infra/ changes"
  else
    echo "    ⚠ May not trigger on infra/ changes — check path filters"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo "  ✗ No terraform plan workflow found"
  echo "    Expected: a workflow that runs 'terraform plan' on PRs"
  ISSUES=$((ISSUES + 1))
fi

# Check for terraform apply workflow
APPLY_WF=$(find "$WORKFLOWS_DIR" -name "*.yml" -exec grep -l "terraform.*apply\|terraform_apply\|tf-apply\|infra.*apply" {} \; 2>/dev/null | head -1)
if [[ -n "$APPLY_WF" ]]; then
  echo "  ✓ Apply workflow: $(basename "$APPLY_WF")"

  # Check for approval/environment protection
  if grep -qE "environment:|approval|manual" "$APPLY_WF" 2>/dev/null; then
    echo "    ✓ Has environment protection/approval"
  else
    echo "    ⚠ No environment protection found — production deploys may not require approval"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo "  ✗ No terraform apply workflow found"
  echo "    Expected: a workflow that runs 'terraform apply' on merge"
  ISSUES=$((ISSUES + 1))
fi

# Check CODEOWNERS for infra/
CODEOWNERS="$REPO_ROOT/.github/CODEOWNERS"
if [[ -f "$CODEOWNERS" ]]; then
  if grep -q "infra/" "$CODEOWNERS" 2>/dev/null; then
    echo "  ✓ CODEOWNERS covers infra/"
  else
    echo "  ⚠ CODEOWNERS exists but doesn't cover infra/"
    ISSUES=$((ISSUES + 1))
  fi
elif [[ -f "$REPO_ROOT/CODEOWNERS" ]]; then
  if grep -q "infra/" "$REPO_ROOT/CODEOWNERS" 2>/dev/null; then
    echo "  ✓ CODEOWNERS covers infra/"
  else
    echo "  ⚠ CODEOWNERS exists but doesn't cover infra/"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo "  ⚠ No CODEOWNERS file found"
  ISSUES=$((ISSUES + 1))
fi

# Check for .terraform.lock.hcl
LOCK_FILE=$(find "$REPO_ROOT/infra" -name ".terraform.lock.hcl" 2>/dev/null | head -1)
if [[ -n "$LOCK_FILE" ]]; then
  # Check if it's tracked in git
  if git ls-files --error-unmatch "$LOCK_FILE" > /dev/null 2>&1; then
    echo "  ✓ Terraform lock file committed"
  else
    echo "  ⚠ Terraform lock file exists but not committed to git"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo "  ⚠ No .terraform.lock.hcl found in infra/"
  ISSUES=$((ISSUES + 1))
fi

echo ""
if [[ $ISSUES -eq 0 ]]; then
  echo "  ✓ All workflow checks passed"
else
  echo "  ⚠ $ISSUES issue(s) found — review before creating PR"
fi
echo ""

# Don't fail the step on warnings — just inform
exit 0
