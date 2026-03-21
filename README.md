# Dream Team Flow

AI-powered workflows for your entire team — developers, infra, data, product, QA, marketing, sales. One CLI to install, role-based setup, customizable workflow steps.

## Install

```bash
# New user — full setup with role selection
dtf install <REPO_URL> --company-config company-config.json

# Existing user — add role and workflow steps
dtf configure
```

## What's Included

| Type | Count | Highlights |
|------|-------|-----------|
| **Agents** | 29 (8 domains) | Engineering, data, infra, testing, product, marketing, design, operations |
| **Skills** | 42 | Conventions, performance, code review, security, workflows per role |
| **Commands** | 21 | Dream Team orchestration, PR review, ticket triage, infra workflows |
| **Scripts** | 33 | Quality gates, terraform plan, memory health, cost tracking |
| **Roles** | 12 | Frontend, Backend, Fullstack, Data, Infra, QA, UAT, PO, Sales, Marketing, Ops |

## Agents (29)

Organized by domain. Your role determines which load — not all 29.

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

## Commands

| Command | Purpose |
|---------|---------|
| `/create-stories` | Full lifecycle orchestrator — ticket to PR for one or more tickets |
| `/my-dream-team` | Multi-agent team implementation with `--lite`, `--local`, `--resume` flags |
| `/infra-ticket` | Terraform workflow — Jira → branch → plan → PR with structured plan summary |
| `/review-pr` | Line-level PR review. `--full` for local builds, `--deep` for multi-agent |
| `/workspace-launch` | Create worktree from Jira ticket + spin up session |
| `/workspace-cleanup` | Tear down worktree, tmux, branch |
| `/ticket-scout` | Batch sprint triage with story point estimation |
| `/ticket-refine` | Deep quality gate for a single ticket |
| `/ticket-examples` | Code variation examples from codebase patterns |
| `/tdd` | Test-driven development loop (red → green → refactor) |
| `/design-an-interface` | 3 parallel agents with different constraints ("Design It Twice") |
| `/triage-issue` | Bug investigation → root cause → Jira ticket with fix plan |
| `/request-refactor-plan` | Interview → codebase exploration → tiny-commit plan → Jira ticket |
| `/evolve` | Review tool usage patterns and promote to skills/conventions |
| `/reviewers` | Manage PR reviewer assignments per category |
| `/team-stats` | Dream Team leaderboard and history |
| `/retro-proposals` | Analyze learnings and route improvements |
| `/pr-insights` | Surface review patterns from scraped PR data |
| `/scrape-pr-history` | Extract structured learnings from merged PRs |
| `/scrape-jira-pushback` | Extract learnings from AI ticket reviews |
| `/sync-config` | Push config to GitHub (private + sanitized public) |

## Skills

### Conventions & Performance
| Skill | Purpose |
|-------|---------|
| `frontend-conventions` | React/TypeScript/Tailwind coding style |
| `frontend-performance` | Core Web Vitals, bundle analysis, React rendering, images, caching |
| `backend-conventions` | .NET microservices coding style |
| `backend-performance` | EF Core queries, N+1 detection, caching, async/await, memory |
| `infra-conventions` | Terraform, AWS, WAF, monitoring, ECR, CI/CD patterns |
| `aws-performance` | CloudWatch, RDS tuning, auto-scaling, S3 lifecycle, cost optimization |
| `data-conventions` | Data engineering, EF Core, pipelines |

### Workflow Skills
| Skill | Purpose |
|-------|---------|
| `code-insights` | Opt-in refactoring nudges + DTO analysis with mermaid diagrams for PRs |
| `code-review-skill` | React 19, TypeScript, perf, security, architecture review guides |
| `tdd` | Test-driven development (red → green → refactor) |
| `playwright-cli` | Browser automation for testing and visual verification |
| `visual-development-workflow` | Write code, verify visually, iterate |
| `mermaid-diagram` | Diagram creation with syntax validation |
| `memory-hygiene` | Review and clean up memory files to keep token costs low |

### Role-Specific Skills
| Skill | Used by |
|-------|---------|
| `po-workflows` | Product Owner — ticket refinement, sprint planning, impact analysis |
| `testing-workflows` | QA/Tester — test planning, Playwright, bug reporting |
| `uat-workflows` | UAT Stakeholder — acceptance criteria, permission testing, Jira bug reports |
| `data-analysis-workflows` | Data Analyst — SQL, notebooks, visualization |
| `presentation-workflows` | Sales — proposals, ROI models, competitive analysis |
| `content-workflows` | Marketing — blog posts, campaigns, SEO, email marketing |
| `context-modes` | All — dev/review/research mindsets |
| `strategic-compact` | All — when/how to compact context at phase boundaries |

### Security & Audit Skills (installed separately)
| Skill | Source | What it does |
|-------|--------|-------------|
| `trailofbits-differential-review` | Trail of Bits (3.8k stars) | Security analysis scoped to changed files |
| `trailofbits-insecure-defaults` | Trail of Bits | Hardcoded credentials, insecure configs |
| `trailofbits-static-analysis` | Trail of Bits | CodeQL/Semgrep with SARIF parsing |
| `trailofbits-supply-chain` | Trail of Bits | Dependency threat analysis |
| `ln-620-codebase-auditor` | levnikolaevich (234 stars) | Full codebase audit orchestrator |
| `ln-621-security-auditor` | levnikolaevich | Secrets, SQL injection, XSS |
| `ln-624-code-quality-auditor` | levnikolaevich | Complexity, N+1, god classes |
| `ln-628-concurrency-auditor` | levnikolaevich | Race conditions, deadlocks, blocking I/O |
| `ln-643-api-contract-auditor` | levnikolaevich | Entity leakage, missing DTOs |
| `ln-650-persistence-performance-auditor` | levnikolaevich | Query + transaction + runtime perf |
| `ln-651-query-efficiency-auditor` | levnikolaevich | N+1, over-fetching, missing bulk ops |
| `ln-653-runtime-performance-auditor` | levnikolaevich | Blocking I/O, allocations, string concat |

## Scripts

### Quality & Workflow
| Script | Purpose |
|--------|---------|
| `quality-gate.sh` | Deterministic pre-push checks (formatting, linting, builds) |
| `terraform-plan-summary.sh` | Structured terraform plan with add/change/destroy counts |
| `verify-infra-workflows.sh` | Checks GH Actions plan/apply exist, CODEOWNERS, lock files |
| `memory-health.sh` | Memory size check with suggestions (0 token cost) |

### Analytics & Optimization
| Script | Purpose |
|--------|---------|
| `analyze-patterns.sh` | Detect recurring patterns from tool usage logs |
| `cost-tracker.sh` | Session cost reports |
| `config-scan.sh` | Security/health scan of Claude config (grades A-F) |

### Workspace Management
| Script | Purpose |
|--------|---------|
| `dtf.sh` | Main CLI — install, configure, steps, update, doctor, contribute |
| `allocate-ports.sh` | Worktree port allocation (3100-3199) |

## Custom Workflow Steps

Every role gets defaults. Customize anytime:

```bash
dtf steps list              # see your steps
dtf steps add               # add automated check or reminder
dtf steps remove            # remove a step
dtf steps reset             # reset to role defaults
```

## Roles

| Role | Agents | Skills | Default Steps |
|------|--------|--------|--------------|
| Frontend Dev | 5 | frontend-conventions, frontend-performance, tdd, code-insights | ESLint, code insights, visual verification, screenshot, a11y |
| Backend Dev | 5 | backend-conventions, backend-performance, tdd, code-insights | CSharpier, tests, code insights, swagger |
| Fullstack | 7 | all dev skills + code-insights | all dev steps |
| Data Engineer | 4 | data-conventions, data-analysis-workflows | dbt build, dbt test, SQL review |
| Data Analyst | 2 | data-analysis-workflows | notebook cleanup, docs, findings |
| Infra/DevOps | 3 | infra-conventions, aws-performance | tf fmt, validate, plan, WAF, monitoring, tags, GH Actions |
| QA/Tester | 3 | testing-workflows, playwright-cli | test plan, all tests, coverage |
| UAT Stakeholder | 1 | uat-workflows | AC listed, roles tested, permissions, bugs filed |
| Product Owner | 4 | po-workflows | impact analysis, AC written, stakeholders notified |
| Sales | 3 | presentation-workflows | data sources, ROI, customer data |
| Marketing | 3 | content-workflows | SEO, multi-language, brand voice |
| Customer Ops | 2 | — | patterns checked, mapping validated, staging test |

## Recommended External Plugins

See `docs/dtf-roles.md` for the full catalog with install commands, organized by role.

## Cost Architecture

- **Baseline per prompt:** ~5,750 tokens (CLAUDE.md + MEMORY.md + system) = 0.6% of context
- **Skills, agents, auditors:** 0 tokens until invoked
- **Scripts (bash):** 0 tokens — run outside Claude
- **Hooks (claudekit):** 0 tokens — run externally

## Docs

| Doc | Purpose |
|-----|---------|
| `docs/dtf-roles.md` | Full role reference — agents, skills, steps, plugins, personalization guide |
| `docs/integrations.md` | Team setup, DTF architecture, onboarding |
| `docs/instruction-delivery.md` | How CLAUDE.md, skills, commands, agents, hooks, memory work together |
| `docs/learning-system.md` | How DTF improves over time (retro → learnings → conventions) |
| `CHANGELOG.md` | Version history |
