Hey! :wave:

We've built a new workflow in Dream Team Flow specifically for infra/DevOps work. Same CLI the dev team uses, but tailored for Terraform, AWS, and CI/CD — with automated checks instead of having to remember everything manually.

*What you get:*
• An AI assistant that knows your stack — WAF, CloudWatch, RDS, ECR, Terraform
• Automated checks: `terraform fmt`, `validate`, plan summary with add/change/destroy counts
• Workflow steps you can customize yourself — add, remove, adjust to how you work
• `/infra-ticket` — one command that takes a Jira ticket all the way to a PR with the plan in the body

---

*Getting started (10 min)*

*1. Install Claude Code*
```
npm install -g @anthropic-ai/claude-code
```

*2. Install DTF with the infra role*
```
dtf install <REPO_URL> --company-config company-config.json
```
The wizard asks you:
• Name + GitHub username
• Path to the repo
• Terminal (Alacritty, iTerm, etc.)
• *Role* → pick `6. Infrastructure / DevOps`
• *Workflow steps* → you get defaults and can customize right away

*3. Done!*
You now have:
— 3 AI agents: `infra-engineer`, `ci-cd-engineer`, `security-auditor`
— 2 skills: `infra-conventions` (Terraform/AWS/WAF/monitoring), `aws-performance` (cost/perf)
— 8 automated workflow steps

---

*Your workflow steps (defaults)*

These run automatically at the right phase:

```
before-commit:
  ⚡ terraform fmt -check -recursive
  ⚡ terraform validate
  📋 No secrets in code

before-push:
  ⚡ terraform plan (structured summary)
      ┌─────────────────────────────┐
      │   Terraform Plan Summary    │
      │   Resources to add:    +2   │
      │   Resources to change: ~1   │
      │   Resources to destroy: -0  │
      └─────────────────────────────┘

before-pr:
  📋 WAF rules: rate limits set
  📋 Monitoring: alarms + Slack channel
  📋 Tags on all resources
  ⚡ GH Actions workflows verified
      (checks that plan/apply workflows exist,
       trigger on infra/, CODEOWNERS covers it)
```

⚡ = runs automatically | 📋 = checklist you confirm manually

---

*Customize your flow*

You can change steps at any time:

```
# View your steps
dtf steps list

# Add a custom step
dtf steps add
  → "ECR scan check"
  → automated
  → "aws ecr describe-image-scan-findings ..."
  → before-pr

# Remove a step
dtf steps remove

# Reset to defaults
dtf steps reset
```

Want to switch roles or start over with steps:
```
dtf configure
```

---

*Daily work — ticket to PR*

```
/infra-ticket PROJ-2345
```

Here's what happens:
1. Fetches the ticket from Jira
2. Creates branch `PROJ-2345-rds-monitoring`
3. Explores `infra/` — finds relevant modules
4. Runs `terraform init`
5. Implements with the AI assistant (understands your Terraform structure)
6. Runs all workflow steps automatically
7. Pushes + creates PR with terraform plan in the body
8. Verifies that GH Actions plan/apply workflows cover the changes

You can also work freely with Claude Code without `/infra-ticket` — the agent has context about your WAF setup, monitoring patterns, ECR config etc regardless.

---

*Questions?*
• `dtf doctor` — check that everything is installed correctly
• `dtf steps list` — see your current steps
• `dtf help` — all commands

Give it a try and let us know if you want to adjust anything! :rocket:
