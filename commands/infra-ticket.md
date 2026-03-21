# Infra Ticket — Terraform Workspace Setup

You are setting up an infrastructure workspace from a Jira ticket. This is like `/workspace-launch` but tailored for Terraform/infra work.

## Config Resolution

Read `~/.claude/dtf-config.json` if it exists. Use:
- `paths.monorepo` instead of hardcoded paths
- `paths.worktreeParent` for worktree location
- `terminal` for opening new windows
If no config exists, fall back to the values in `~/.claude/CLAUDE.md`.

## Input

The user provides either:
- A **ticket ID** (e.g., `PROJ-2345`)
- A description of the infra change needed

$ARGUMENTS

## Workflow

### Step 0: Quick Health Check

Run memory health check (0 token cost, bash script):
```bash
bash ~/.claude/scripts/memory-health.sh
```
If warnings are found, show them briefly and ask: "Want to clean up memory first, or continue to the ticket?" — then move on regardless.

### Step 1: Fetch Ticket

```bash
acli jira workitem view <TICKET_ID>
```

If ACLI fails, ask the user to describe the task.

Read the ticket carefully. Identify:
- Which AWS resources are affected (RDS, S3, WAF, EC2, ServiceC, etc.)
- Which Terraform modules need changes
- Whether this is a new resource, modification, or deletion
- Which environments are affected (dev, accept, prod)

### Step 2: Create Branch

```bash
cd <MONOREPO_PATH>
git fetch origin main
git checkout -b <TICKET_ID>-<short-description> origin/main
```

Branch naming: `PROJ-2345-rds-monitoring` (ticket + kebab-case summary).

### Step 3: Explore Infra Structure

Map the relevant Terraform modules:

```bash
# Find relevant modules
find infra/ -name "*.tf" | head -30

# Check existing module structure
ls infra/modules/

# Find files related to the ticket's resources
grep -r "aws_db_instance\|aws_rds" infra/ --include="*.tf" -l
```

Present the user with:
- Which modules exist
- Which files are relevant to this ticket
- Whether a new module is needed or existing ones should be modified

### Step 4: Terraform Init

Ensure Terraform is initialized for the relevant workspace:

```bash
cd infra/
terraform init
```

If there are multiple workspaces/environments:
```bash
terraform workspace list
terraform workspace select <environment>
```

### Step 5: Pre-flight Checks

Before making changes, verify:

1. **Provider versions locked:**
   ```bash
   grep -r "required_providers" infra/ --include="*.tf" -A 5
   ```

2. **No pending state drift:**
   ```bash
   terraform plan -detailed-exitcode
   # Exit code 0 = no changes, 2 = changes detected
   ```

3. **Current state is clean** — if there's drift, flag it to the user before proceeding.

### Step 6: Implement Changes

Use the `infra-engineer` agent for Terraform changes. Always follow:

- **Safety**: `prevent_destroy` on critical resources
- **Naming**: `{service}-{environment}-{resource-type}`
- **Tagging**: Every resource gets `environment`, `service`, `managed-by` tags
- **Variables**: Descriptive names with `description` and `type` fields
- **Secrets**: Never in code — use AWS Secrets Manager or Parameter Store

For each change:
1. Modify the Terraform files
2. Run `terraform fmt -recursive`
3. Run `terraform validate`
4. Run `terraform plan` and review the output

### Step 7: Terraform Plan Review

Run plan and present a structured summary:

```bash
terraform plan -out=tfplan 2>&1
```

Present to the user:
```
## Terraform Plan Summary

**Resources to add:** 2
  + aws_service-c_role.rds_monitoring
  + aws_cloudwatch_metric_alarm.rds_cpu_high

**Resources to change:** 1
  ~ aws_db_instance.prod (monitoring_interval: 0 → 60)

**Resources to destroy:** 0

**Risk assessment:**
- No destructive changes
- ServiceC role follows least privilege
- Monitoring change is non-breaking
```

If the plan includes **any destroy operations**, STOP and explicitly warn the user.

### Step 8: Workflow Steps

Run the configured workflow steps before push:

```bash
# Read steps from config
jq -r '.workflowSteps[] | select(.when == "before-commit") |
  if .type == "automated" then "⚡ Running: \(.command)"
  else "📋 Reminder: \(.name)" end' ~/.claude/dtf-config.json
```

Execute automated steps and show reminders:

**before-commit:**
- ⚡ `terraform fmt -check -recursive` → must pass
- 📋 No secrets in code → user confirms

**before-push:**
- ⚡ `terraform plan` → show summary
- 📋 Review plan output

**before-pr:**
- 📋 Security scan completed
- 📋 CODEOWNERS covers changed paths

### Step 9: Push & Create PR

```bash
git add infra/
git commit -m "PROJ-2345: Enable RDS Enhanced Monitoring

- Enable Enhanced Monitoring (60s granularity) on prod RDS instances
- Add ServiceC role for RDS monitoring
- Add CloudWatch alarm for CPU > 80%

Co-Authored-By: Claude <noreply@anthropic.com>"

git push -u origin <BRANCH>
```

Create PR with terraform plan in the body:

```bash
gh pr create --title "PROJ-2345: Enable RDS Enhanced Monitoring" --body "$(cat <<'EOF'
## Summary
- Enable Enhanced Monitoring (60s) on production RDS instances
- Add CloudWatch CPU alarm (threshold: 80%)
- Add dedicated ServiceC monitoring role

## Terraform Plan
```
<paste plan output>
```

## Checklist
- [ ] `terraform plan` reviewed
- [ ] No secrets in code
- [ ] No destroy operations
- [ ] CODEOWNERS covers infra/ changes
- [ ] Security implications reviewed

## Test plan
- [ ] Verify plan output matches expected changes
- [ ] After merge: confirm GH Actions `terraform-apply` runs
- [ ] After apply: verify Enhanced Monitoring active in AWS Console
- [ ] After apply: verify CloudWatch alarm created

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 10: Verify GitHub Actions

After PR creation, check that the plan/apply workflows exist for the changed modules:

```bash
# Check if terraform plan workflow exists
ls .github/workflows/terraform-plan.yml 2>/dev/null && echo "✓ Plan workflow exists" || echo "⚠ No plan workflow found"

# Check if terraform apply workflow exists
ls .github/workflows/terraform-apply.yml 2>/dev/null && echo "✓ Apply workflow exists" || echo "⚠ No apply workflow found"

# Verify the workflows cover the changed paths
grep -l "infra/" .github/workflows/*.yml 2>/dev/null
```

If workflows are missing, offer to create them using the `ci-cd-engineer` agent.

### Step 11: Post-PR Summary

Present final summary:

```
## ✓ Infra Ticket Complete

**Ticket:** PROJ-2345
**Branch:** PROJ-2345-rds-monitoring
**PR:** #<number>

**Changes:**
- infra/modules/rds/main.tf (monitoring config)
- infra/modules/monitoring/alarms.tf (new CPU alarm)
- infra/modules/rds/service-c.tf (monitoring ServiceC role)

**What happens next:**
1. GH Actions runs `terraform plan` → posted as PR comment
2. Infra team reviews (CODEOWNERS)
3. After approval + merge → `terraform apply` with manual prod approval
4. Verify in AWS Console after apply
```
