# DTF Changelog — March 2026

## Role-Based Flows (New)

DTF now supports 12 roles beyond just developers. Each person picks their role during setup and gets tailored agents, skills, workflow steps, and plugin recommendations.

**Roles:** Developer (Frontend, Backend, Fullstack), Data Engineer, Data Analyst, Infrastructure/DevOps, QA/Tester, UAT Stakeholder, Product Owner, Sales, Marketing, Customer Operations

**Setup:**
```bash
dtf install <REPO_URL> --company-config company-config.json  # new users
dtf configure                                                  # existing users
```

**What your role determines:**
- Which AI agents are available (3-7 per role)
- Which skills/conventions load (performance, testing, infra, etc.)
- Default workflow steps (automated checks + reminders)
- Recommended external plugins

## Custom Workflow Steps (New)

Build your own workflow — add, remove, or customize steps that run at different phases.

```bash
dtf steps list              # see your steps
dtf steps add               # add a custom step
dtf steps remove            # remove a step
dtf steps reset             # reset to role defaults
```

**Two step types:**
- `automated` (⚡) — runs a shell command and reports pass/fail
- `reminder` (📋) — checklist item you confirm manually

**Five phases:** `on-start`, `before-commit`, `before-push`, `before-pr`, `after-pr`

## Agent Reorganization (29 agents, 8 domains)

```
agents/
├── engineering/     (7)  frontend-dev, backend-dev, architect, pr-reviewer,
│                         api-designer, performance-analyst, migration-planner
├── data/            (4)  data-engineer, data-analyst, pipeline-builder, insights-reporter
├── design/          (2)  ui-designer, ux-researcher
├── infrastructure/  (3)  infra-engineer, ci-cd-engineer, security-auditor
├── marketing/       (4)  marketing-ops, sales-enablement, content-creator, social-strategist
├── operations/      (2)  customer-ops, support-responder
├── product/         (3)  po-analyst, requirements-analyst, sprint-prioritizer
└── testing/         (4)  qa-tester, uat-tester, api-tester, performance-benchmarker
```

Your role loads only the relevant agents — not all 29.

## Performance Skills (New)

Three new skills with actionable checklists based on developer-roadmap.sh (49 frontend + 47 backend + 50 AWS items) and best-in-class external skills:

| Skill | What it covers |
|-------|---------------|
| `frontend-performance` | Core Web Vitals, bundle analysis, React rendering, image optimization, RTK Query |
| `backend-performance` | EF Core queries, N+1 detection, caching, async/await, memory, serialization |
| `aws-performance` | CloudWatch, RDS tuning, auto-scaling, S3 lifecycle, cost optimization quick wins |

## Code Insights — Opt-In Refactoring (New)

After your first draft, say "check my changes" or `/code-insights`:

**Quick nudges** — scans only your changed files for 10 frontend + 10 backend patterns:
```
📌 UserList.tsx:42 — Computation in render
   Now:     items.sort(...).map(...) in JSX
   Better:  useMemo(() => items.sort(...), [items])
   ✅ Why:   Re-sorts every render
   ⏭️ Skip if: List < 10 items
```

**DTO & architecture insights** — deeper analysis with mermaid diagrams, ready to paste in PR description.

## Infrastructure Flow (New)

`/infra-ticket` — full Terraform workflow: Jira → branch → explore modules → implement → plan → PR.

**New scripts (0 token cost):**
- `terraform-plan-summary.sh` — structured plan with add/change/destroy box, warns on destroys
- `verify-infra-workflows.sh` — checks GH Actions plan/apply exist, CODEOWNERS, lock files

**Default infra steps:**
```
before-commit: ⚡ terraform fmt, ⚡ terraform validate, 📋 No secrets
before-push:   ⚡ terraform plan (structured summary)
before-pr:     📋 WAF rules, 📋 Monitoring/Slack, 📋 Tags, ⚡ GH Actions verified
```

## Memory Hygiene (New)

Memory files grow over time and cost tokens every prompt. New system to keep them in check:

- `memory-health.sh` — bash script, 0 token cost, shows memory size + suggestions
- `memory-hygiene` skill — triggered at session-start in `/create-stories`, `/workspace-launch`, `/infra-ticket`
- Never triggers during compact or active work — only when context is clean

```bash
bash ~/.claude/scripts/memory-health.sh

  🧹 Memory Health Check
  MEMORY.md:            136 lines / 1,827 tokens ⚠️ over budget
  dream-team-learnings: 615 lines — consider archiving
  💡 1. Archive large memory files
  💡 2. Run /retro-proposals then archive old learnings
```

## Installed Plugins (New)

**Code review & quality:**
- `code-review-skill` (159 stars) — React 19, TypeScript, perf, security guides
- `claudekit` (633 stars) — real-time hooks, catches issues as you write

**Security (Trail of Bits, 3.8k stars):**
- `differential-review` — security analysis scoped to changed files
- `insecure-defaults` — hardcoded credentials, insecure configs
- `static-analysis` — CodeQL/Semgrep with SARIF parsing
- `supply-chain-risk-auditor` — dependency threat analysis

**Codebase audit (levnikolaevich, 234 stars):**
- 8 auditors: security, code quality, concurrency, API contracts, query efficiency, persistence performance, runtime performance, codebase orchestrator

**Frontend performance:**
- Vercel React Best Practices (21k+ stars) — 45 rules
- Addy Osmani Web Quality (1.2k stars) — Lighthouse + Core Web Vitals

**Backend/.NET:**
- dotnet-skills (658 stars) — 30 skills + 5 agents, EF Core, concurrency
- Official Microsoft .NET skills

**Infrastructure:**
- TerraShark (47 stars) — failure-mode Terraform
- AWS cost ops (200 stars) — cost optimization with MCP

## Company Config with Roles (New)

`company-config.json` now includes role definitions — share with team members so `dtf install` knows which agents/skills to set up per role.

## Stats

| What | Count |
|------|-------|
| Agents | 29 (in 8 domains) |
| Skills | 42 |
| Commands | 21 |
| Scripts | 33 |
| Roles | 12 |
| Installed plugins | 15 |
| Token cost baseline | ~5,750 per prompt (0.6% of context) |
| Everything else | 0 tokens until used |
