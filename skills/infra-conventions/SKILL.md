---
name: infra-conventions
description: Infrastructure and DevOps conventions — Terraform, AWS, CI/CD, monitoring, and security for Repo
---

## Terraform Conventions

### Structure
- One module per logical resource group (e.g., `monitoring`, `waf`, `rds`)
- Use strict provider version pinning (`required_providers` block)
- Lock files committed to repo
- Variables: descriptive names with `description` and `type` fields
- Outputs: expose only what consumers need

### State Management
- Remote state in S3 with DynamoDB locking
- One state file per environment (dev, accept, prod)
- Never manually edit state — use `terraform import` / `terraform state mv`

### Safety
- Always `terraform plan` before `terraform apply`
- Production changes require approval step in CI
- Use `prevent_destroy` lifecycle for critical resources
- Tag all resources with `environment`, `service`, `managed-by`

## AWS Conventions

### Security
- KMS customer-managed keys for S3 encryption
- SSL enforcement for all RDS instances
- ECR immutable tags and vulnerability scanning
- ServiceC least-privilege — no wildcard `*` actions
- WAF rate limiting on all public endpoints

### Monitoring
- CloudWatch alarms for CPU, memory, disk, and custom metrics
- SNS topics → Slack channels for alerts
- RDS Enhanced Monitoring + Performance Insights enabled
- OpenTelemetry for log/trace correlation

### Naming
- Resources: `{service}-{environment}-{resource-type}` (e.g., `service-c-prod-rds`)
- ServiceC roles: `{service}-{action}-role` (e.g., `ecr-scan-role`)

## WAF Configuration (Common Task)

### Rate Limiting
```hcl
resource "aws_wafv2_rate_based_statement" "api_rate_limit" {
  limit              = 2000
  aggregate_key_type = "IP"
  # Always set per-environment: dev=10000, accept=5000, prod=2000
}
```

### IP Whitelisting
- Admin endpoints: whitelist known IPs
- Internal APIs: VPC-only or security group restricted
- Public APIs: WAF rate limiting + managed rule groups

### Environment Toggles
- Dev: WAF disabled or permissive (for testing)
- Accept: WAF enabled, relaxed rules
- Prod: WAF enabled, strict rules, all logging on

### CrossSiteScripting Exceptions
When legitimate payloads trigger XSS rules, add targeted exceptions — never disable the rule globally.

## Monitoring Patterns (Common Task)

### CloudWatch Alarms → SNS → Slack
```hcl
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.service}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alerts.arn]
  # Tag: environment, service
}
```

### Slack Channels
- Separate channels per environment: `#alerts-prod`, `#alerts-accept`
- Include service name in alarm so oncall knows which service is affected

### RDS Enhanced Monitoring
- Enable 60s granularity on production
- Requires dedicated ServiceC role for monitoring
- Performance Insights for query-level analysis

### OpenTelemetry
- JSON parsing for structured logs
- Trace correlation (trace_id in log entries)
- Service name via environment variable (`OTEL_SERVICE_NAME`)

## ECR Security (Common Task)

```hcl
resource "aws_ecr_repository" "service" {
  name                 = var.service_name
  image_tag_mutability = "IMMUTABLE"  # Always immutable in prod

  image_scanning_configuration {
    scan_on_push = true  # Scan every push
  }
}
```

- Registry-level scan settings (not per-repo)
- Vulnerability reports as CI artifacts
- Lifecycle policies: keep last 10 tagged images, delete untagged after 7 days

## RDS Security (Common Task)

- SSL enforcement: `rds.force_ssl = 1` in parameter group
- CA trust configuration for certificate rotation
- Customer-managed KMS keys for encryption at rest
- Automated backups with cross-region copy for DR
- Connection pooling: match `max_connections` to instance size

## CI/CD (GitHub Actions)

### Workflows
- `terraform-plan.yml` — runs on PR, posts plan as comment
- `terraform-apply.yml` — runs on merge to main, requires approval for prod
- Separate Slack notification channels for prod vs accept
- CODEOWNERS for `infra/` directory

### Deployment Notifications
```yaml
# Separate channels per environment
- if: env.ENVIRONMENT == 'production'
  run: send-to-slack channel="#deploy-prod"
- if: env.ENVIRONMENT == 'accept'
  run: send-to-slack channel="#deploy-accept"
```

### Workflow Permissions
- Minimal GitHub token permissions per workflow
- Never use `permissions: write-all`
- ECR immutable tags prevent accidental overwrites

### Security
- No secrets in code — use GitHub Secrets + AWS Secrets Manager
- ECR vulnerability reports as CI artifacts
- Dependabot for provider version updates

## Automated Quality Scripts

DTF includes two scripts for infra workflow steps:

- **`terraform-plan-summary.sh`** — Runs `terraform plan` and shows a structured summary box with add/change/destroy counts. Warns loudly on destroy operations.
- **`verify-infra-workflows.sh`** — Checks that GH Actions plan/apply workflows exist, trigger on `infra/`, have environment protection, CODEOWNERS covers the path, and lock files are committed.

## Recommended External Skills

Install for enhanced Terraform support:
```bash
# TerraShark — failure-mode-first Terraform skill (600 tokens activation)
git clone https://github.com/LukasNiessen/terrashark.git ~/.claude/skills/terrashark

# Terramate agent skills — 37 rules across 10 categories
npx skills add terramate-io/agent-skills --skill terraform-best-practices

# AWS cost optimization with MCP servers
/plugin marketplace add zxkane/aws-skills
```
