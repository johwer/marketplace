# DTF — Role-Based Flows

Dream Team Flow supports any role in your organization, not just developers.
Each person picks their role during setup and gets a tailored experience: agents, skills, workflow steps, and plugin recommendations.

## Table of Contents

- [Quick Start](#quick-start)
- [Available Roles](#available-roles)
- [CLI Commands](#cli-commands)
- [Custom Workflow Steps](#custom-workflow-steps)
- [Agents](#agents)
- [Skills](#skills)
- [Recommended Plugins](#recommended-plugins)
- [Configuration](#configuration)
- [Company Config](#company-config)

---

## Quick Start

```bash
# New user — install with role selection
dtf install <REPO_URL> --company-config company-config.json

# Existing user — add role and workflow steps
dtf configure

# Manage your workflow anytime
dtf steps list
dtf steps add
dtf steps remove
```

## Personalize Your Workflow

DTF gives every user their own workflow — you pick a role, get sensible defaults, and customize from there.

### 1. Choose Your Role

During `dtf install` or anytime with `dtf configure`:

```
$ dtf configure

=== Configure Your Role & Workflow ===

  Current role: not set

  What's your primary role?
    1. Developer (Frontend)
    2. Developer (Backend)
    3. Developer (Fullstack)
    ...
    12. Customer Operations
  Choose [1]: 1
  ✓ Role: Developer (Frontend) (frontend-dev)
```

Your role determines:
- **Agents**: Which AI specialists are available (e.g., `frontend-dev` + `architect` + `pr-reviewer`)
- **Skills**: Which conventions and workflows load (e.g., `frontend-conventions` + `frontend-performance`)
- **Default steps**: Checklist and automated checks for your workflow

### 2. Customize Your Steps

Each role comes with default steps. You can accept them as-is or customize:

```
$ dtf configure
  ...
  Default workflow steps for Developer (Frontend):
  [before-commit] ESLint check (automated)
  [before-pr] Visual verification (reminder)
  [before-pr] Screenshot capture (reminder)
  [before-pr] Accessibility check (reminder)

  Customize these steps? (y/N): y
```

### 3. Manage Steps Anytime

Add, remove, or reset steps without reconfiguring your entire role:

```bash
# See your current steps
$ dtf steps list
  [before-commit]
    ⚡ ESLint check → npm run lint
  [before-pr]
    📋 Visual verification
    📋 Screenshot capture
    📋 Accessibility check

  ⚡ = automated  📋 = reminder

# Add a custom step
$ dtf steps add
  Step name: Run Vitest
  Step type: 1. reminder  2. automated
  Choose [1]: 2
  Shell command to run: npm run test
  When to trigger: 1. before-commit  2. before-push  3. before-pr  ...
  Choose [1]: 2
  ✓ Added: [before-push] Run Vitest (automated)

# Remove a step you don't need
$ dtf steps remove
  Current steps:
    1. [before-commit] ESLint check (automated)
    2. [before-push] Run Vitest (automated)
    3. [before-pr] Visual verification (reminder)
  Step number to remove: 3
  ✓ Removed: Visual verification

# Reset to your role's defaults
$ dtf steps reset
  ✓ Reset to default steps for role: frontend-dev
```

### Step Types

| Type | Icon | What happens |
|------|------|-------------|
| **reminder** | 📋 | Shown as a checklist item — you verify manually |
| **automated** | ⚡ | Runs a shell command and reports pass/fail |

### Step Phases

| Phase | When |
|-------|------|
| `on-start` | Beginning of a work session |
| `before-commit` | Before `git commit` |
| `before-push` | Before `git push` |
| `before-pr` | Before creating a pull request |
| `after-pr` | After PR is created |

## Role-Specific Commands

Some roles have dedicated slash commands that orchestrate the full workflow.

### `/infra-ticket` — Infrastructure / Terraform

Full workflow: Jira ticket → explore modules → implement → plan → review → push → PR.

```
$ /infra-ticket PROJ-2345

  1. Fetches ticket from Jira
  2. Creates branch: PROJ-2345-rds-monitoring
  3. Explores infra/ modules, finds relevant files
  4. Runs terraform init
  5. Pre-flight: provider versions, state drift check
  6. Implements changes with infra-engineer agent
  7. Runs workflow steps:
     ⚡ terraform fmt -check -recursive
     ⚡ terraform validate
     📋 No secrets in code
     ⚡ terraform plan (structured summary)
     📋 Security scan
     ⚡ GH Actions workflows verified
  8. Pushes + creates PR with plan output in body
  9. Verifies CODEOWNERS, plan/apply workflows exist
```

**Automated scripts used:**
- `terraform-plan-summary.sh` — runs `terraform plan` and presents a structured box:
  ```
  ┌─────────────────────────────────────┐
  │        Terraform Plan Summary        │
  ├─────────────────────────────────────┤
  │  Resources to add:              +2  │
  │  Resources to change:           ~1  │
  │  Resources to destroy:          -0  │
  └─────────────────────────────────────┘
  ```
  Warns loudly on any destroy operations.

- `verify-infra-workflows.sh` — checks that GH Actions plan/apply workflows exist, trigger on `infra/`, have environment protection, and CODEOWNERS covers the path.

---

## Available Roles

| # | Role | Agent | Skills | Model |
|---|------|-------|--------|-------|
| 1 | Developer (Frontend) | `frontend-dev` | frontend-conventions, tdd | Sonnet |
| 2 | Developer (Backend) | `backend-dev` | backend-conventions, tdd | Sonnet |
| 3 | Developer (Fullstack) | `frontend-dev` + `backend-dev` | all dev skills | Sonnet |
| 4 | Data Engineer | `data-engineer` | data-conventions, data-analysis-workflows | Sonnet |
| 5 | Data Analyst | `data-analyst` | data-analysis-workflows | Sonnet |
| 6 | Infrastructure / DevOps | `infra-engineer` | infra-conventions | Sonnet |
| 7 | QA / Tester | `qa-tester` | testing-workflows, playwright-cli | Sonnet |
| 8 | UAT / QA Stakeholder | `uat-tester` | uat-workflows | Sonnet |
| 9 | Product Owner | `po-analyst` | po-workflows | Opus |
| 10 | Sales | `sales-enablement` | presentation-workflows | Sonnet |
| 11 | Marketing | `marketing-ops` | content-workflows | Sonnet |
| 12 | Customer Operations | `customer-ops` | — | Sonnet |

Supporting roles (available to all):
- **Architect** (`architect`, Opus) — Architecture analysis and implementation plans
- **PR Reviewer** (`pr-reviewer`, Opus) — Line-level code review

---

## CLI Commands

### `dtf install`

First-time setup. Clones the workflow repo, runs the interactive wizard, creates symlinks.

```bash
dtf install <REPO_URL> [--company-config <path>] [--to <dir>]
```

The wizard asks for:
1. Name and GitHub username
2. Monorepo path and worktree parent
3. Terminal preference
4. **Role selection** — determines agents, skills, and default workflow steps
5. **Workflow step customization** — accept defaults, remove, or add custom steps
6. Extra paths (from company config)

### `dtf configure`

Change your role and workflow steps **without reinstalling**. Works for existing users who installed before role support was added.

```bash
dtf configure
```

This updates your `dtf-config.json` to version 2 with role and workflow step data while preserving all existing settings.

### `dtf steps`

Manage your personal workflow steps at any time.

```bash
dtf steps list          # Show steps grouped by phase
dtf steps add           # Add a new step (guided)
dtf steps remove        # Remove a step by number
dtf steps reset         # Reset to your role's defaults
```

### Other Commands

```bash
dtf update              # Pull latest, verify symlinks, regenerate CLAUDE.md
dtf apply-config <path> # Apply company config (de-sanitize names)
dtf doctor              # Health check
dtf contribute          # Export learnings as PR to workflow repo
dtf version             # Show version
```

---

## Custom Workflow Steps

Every role gets default workflow steps. You can customize them during install, via `dtf configure`, or anytime with `dtf steps`.

### Step Schema

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Human-readable description |
| `type` | Yes | `reminder` (checklist item) or `automated` (runs a shell command) |
| `command` | If automated | Shell command to execute |
| `when` | Yes | Phase trigger (see below) |

### Phases

| Phase | When it runs |
|-------|-------------|
| `on-start` | Beginning of a work session |
| `before-commit` | Before committing code |
| `before-push` | Before pushing to remote |
| `before-pr` | Before creating a pull request |
| `after-pr` | After PR is created |

### Default Steps per Role

**Developer (Frontend)**
| Step | Type | Phase |
|------|------|-------|
| ESLint check | automated (`npm run lint`) | before-commit |
| Visual verification | reminder | before-pr |
| Screenshot capture | reminder | before-pr |
| Accessibility check | reminder | before-pr |

**Developer (Backend)**
| Step | Type | Phase |
|------|------|-------|
| CSharpier format | automated (`dotnet csharpier .`) | before-commit |
| Run unit tests | automated (`dotnet test`) | before-push |
| Swagger validation | reminder | before-pr |

**Developer (Fullstack)**
All frontend + backend steps combined.

**Data Engineer**
| Step | Type | Phase |
|------|------|-------|
| dbt build | automated (`dbt build`) | before-push |
| dbt test | automated (`dbt test`) | before-push |
| SQL review | reminder | before-pr |

**Data Analyst**
| Step | Type | Phase |
|------|------|-------|
| Notebook outputs cleared | reminder | before-commit |
| SQL queries documented | reminder | before-push |
| Findings summarized | reminder | before-pr |

**Infrastructure / DevOps**
| Step | Type | Phase |
|------|------|-------|
| No secrets in code | reminder | before-commit |
| Terraform plan | automated (`terraform plan`) | before-push |
| Security scan | reminder | before-pr |
| CODEOWNERS updated | reminder | before-pr |

**QA / Tester**
| Step | Type | Phase |
|------|------|-------|
| Test plan documented | reminder | on-start |
| All tests passing | automated (`npm run test:e2e`) | before-pr |
| Coverage report reviewed | reminder | before-pr |

**UAT / QA Stakeholder**
| Step | Type | Phase |
|------|------|-------|
| Acceptance criteria listed | reminder | on-start |
| All user roles tested | reminder | before-pr |
| Permission matrix verified | reminder | before-pr |
| Bug reports filed | reminder | after-pr |

**Product Owner**
| Step | Type | Phase |
|------|------|-------|
| Impact analysis done | reminder | on-start |
| Acceptance criteria written | reminder | before-pr |
| Stakeholders notified | reminder | after-pr |

**Sales**
| Step | Type | Phase |
|------|------|-------|
| Data sources verified | reminder | on-start |
| ROI calculated | reminder | before-pr |
| Customer-specific data checked | reminder | before-pr |

**Marketing**
| Step | Type | Phase |
|------|------|-------|
| SEO keywords checked | reminder | before-push |
| Multi-language considered | reminder | before-pr |
| Brand voice reviewed | reminder | before-pr |

**Customer Operations**
| Step | Type | Phase |
|------|------|-------|
| Existing customer patterns checked | reminder | on-start |
| Mapping validated | reminder | before-push |
| Acceptance test in staging | reminder | before-pr |

---

## Agents (29 total)

Agents are organized by domain in `~/.claude/agents/`. Your role determines which agents are available — you don't spin up all of them, just the ones relevant to your work.

```
agents/
├── engineering/          # Core development
│   ├── frontend-dev.md
│   ├── backend-dev.md
│   ├── architect.md
│   ├── pr-reviewer.md
│   ├── api-designer.md
│   ├── performance-analyst.md
│   └── migration-planner.md
├── data/                 # Data & analytics
│   ├── data-engineer.md
│   ├── data-analyst.md
│   ├── pipeline-builder.md
│   └── insights-reporter.md
├── design/               # UX & UI
│   ├── ui-designer.md
│   └── ux-researcher.md
├── infrastructure/       # DevOps & security
│   ├── infra-engineer.md
│   ├── ci-cd-engineer.md
│   └── security-auditor.md
├── marketing/            # Content & sales
│   ├── marketing-ops.md
│   ├── sales-enablement.md
│   ├── content-creator.md
│   └── social-strategist.md
├── operations/           # Support & customer
│   ├── customer-ops.md
│   └── support-responder.md
├── product/              # Product management
│   ├── po-analyst.md
│   ├── requirements-analyst.md
│   └── sprint-prioritizer.md
└── testing/              # QA & performance
    ├── qa-tester.md
    ├── uat-tester.md
    ├── api-tester.md
    └── performance-benchmarker.md
```

### Which Agents Load per Role

| Role | Agents (loaded automatically) |
|------|------|
| **Frontend Dev** | `engineering/frontend-dev`, `architect`, `pr-reviewer`, `api-designer`, `design/ui-designer` |
| **Backend Dev** | `engineering/backend-dev`, `architect`, `pr-reviewer`, `api-designer`, `migration-planner` |
| **Fullstack Dev** | `engineering/*` (all 7) |
| **Data Engineer** | `data/data-engineer`, `pipeline-builder`, `insights-reporter`, `architect` |
| **Data Analyst** | `data/data-analyst`, `insights-reporter` |
| **Infra / DevOps** | `infrastructure/*` (all 3) |
| **QA / Tester** | `testing/qa-tester`, `api-tester`, `performance-benchmarker` |
| **UAT Stakeholder** | `testing/uat-tester` |
| **Product Owner** | `product/*` (all 3) + `architect` |
| **Sales** | `marketing/sales-enablement`, `data/data-analyst`, `insights-reporter` |
| **Marketing** | `marketing/marketing-ops`, `content-creator`, `social-strategist` |
| **Customer Ops** | `operations/*` (all 2) |

Agents not in your role are still accessible — they just aren't loaded by default. You can always reference any agent explicitly.

---

## Skills

Skills are workflow guides in `~/.claude/skills/*/SKILL.md`. They load on demand.

### Built-in Skills
| Skill | Directory | Used by |
|-------|-----------|---------|
| `frontend-conventions` | `skills/frontend-conventions/` | Frontend Dev, Fullstack |
| `frontend-performance` | `skills/frontend-performance/` | Frontend Dev, Fullstack |
| `backend-conventions` | `skills/backend-conventions/` | Backend Dev, Fullstack |
| `backend-performance` | `skills/backend-performance/` | Backend Dev, Fullstack |
| `aws-performance` | `skills/aws-performance/` | Infra / DevOps |
| `data-conventions` | `skills/data-conventions/` | Data Engineer |
| `data-analysis-workflows` | `skills/data-analysis-workflows/` | Data Analyst, Data Engineer |
| `infra-conventions` | `skills/infra-conventions/` | Infra / DevOps |
| `testing-workflows` | `skills/testing-workflows/` | QA / Tester |
| `uat-workflows` | `skills/uat-workflows/` | UAT / QA Stakeholder |
| `po-workflows` | `skills/po-workflows/` | Product Owner |
| `presentation-workflows` | `skills/presentation-workflows/` | Sales |
| `content-workflows` | `skills/content-workflows/` | Marketing |
| `tdd` | `skills/tdd/` | Frontend Dev, Backend Dev, Fullstack |
| `playwright-cli` | `skills/playwright-cli/` | QA / Tester, Frontend Dev |
| `mermaid-diagram` | `skills/mermaid-diagram/` | Frontend, Backend, Fullstack, Data Eng, PO |

### General-Purpose Skills
| Skill | What it does |
|-------|-------------|
| `context-modes` | Switch between dev/review/research mindsets |
| `strategic-compact` | Proactive context management at phase boundaries |
| `design-an-interface` | 3-way parallel interface design exploration |
| `grill-me` | Interview-driven design exploration |
| `triage-issue` | Bug investigation + Jira ticket creation |
| `request-refactor-plan` | Refactoring analysis + tiny-commit plan |
| `improve-codebase-architecture` | Architecture audit for agent-friendliness |

---

## Recommended Plugins

External skills and plugins that complement the built-in ones. Install these based on your role.

### Official Plugins (built into Claude Code)

| Plugin | Install | What it does |
|--------|---------|-------------|
| **typescript-lsp** | `/plugin install typescript-lsp@claude-plugins-official` | TypeScript code intelligence: diagnostics, jump-to-def, find references |
| **csharp-lsp** | `/plugin install csharp-lsp@claude-plugins-official` | C# code intelligence (requires `csharp-ls`) |
| **frontend-design** | `/plugin install frontend-design@claude-plugins-official` | Bold aesthetic direction before writing UI code |
| **figma** | `/plugin install figma@claude-plugins-official` | Direct Figma file reading for design-to-code |
| **sentry** | `/plugin install sentry@claude-plugins-official` | Error monitoring integration |
| **pr-review-toolkit** | `/plugin install pr-review-toolkit@claude-plugins-official` | Specialized PR review agents |
| **github** | `/plugin install github@claude-plugins-official` | GitHub MCP integration |

### Code Review & Quality (all dev roles)

| Plugin | Stars | Install | What it does |
|--------|-------|---------|-------------|
| **code-review (Official)** | Built-in | `/code-review` | 4 parallel agents, diff-only, confidence scoring (80+ threshold) |
| **code-review-skill** | 159 | `git clone https://github.com/awesome-skills/code-review-skill ~/.claude/skills/code-review-skill` | React 19, TypeScript, perf, security, architecture guides |
| **Trail of Bits security** | 3.8k | `/plugin marketplace add trailofbits/skills` | Security-focused diff analysis from top security firm. 39 skills |
| **claudekit** | 633 | `npm install -g claudekit && claudekit setup` | Real-time hooks — catches issues as you write, not after |
| **codebase-audit-suite** | 234 | `/plugin add levnikolaevich/claude-code-skills --plugin codebase-audit-suite` | 31 parallel auditors — monthly full audit, not per-PR |

### Frontend Plugins

| Plugin | Stars | Install | What it does |
|--------|-------|---------|-------------|
| **Vercel React Best Practices** | 21k+ | `npx skills add vercel-labs/agent-skills` | 45 rules: async waterfalls, bundle size, re-renders, SSR |
| **Web Quality (Addy Osmani)** | 1.2k | `npx skills add addyosmani/web-quality-skills` | Lighthouse audits, Core Web Vitals, LCP/CLS/INP optimization |
| **tailwind-v4-shadcn** | 86 | `/plugin marketplace add secondsky/claude-skills` | Tailwind v4 + shadcn/ui patterns |
| **React kit** | 74 | `npx github:blencorp/claude-code-kit` | React 19, Tailwind v4, TanStack Query auto-detection |
| **design-motion** | 199 | `npx add-skill kylezantos/design-motion-principles` | Motion design audit, identifies missing animations |
| **a11y-skill** | — | `git clone https://github.com/airowe/claude-a11y-skill ~/.claude/skills/a11y` | WCAG 2.1 AA accessibility audit with axe-core |
| **i18n-expert** | 694 | `/plugin install i18n-expert@daymade-skills` | Internationalization assistance |

### Backend Plugins (.NET)

| Plugin | Stars | Install | What it does |
|--------|-------|---------|-------------|
| **dotnet-skills** | 658 | `/plugin marketplace add Aaronontheweb/dotnet-skills` | 30 skills + 5 agents: EF Core, DI, concurrency, API design, benchmarks |
| **wshaddix/dotnet-skills** | — | `git clone https://github.com/wshaddix/dotnet-skills` | 167 skills: N+1 detection, query optimization, database-performance |
| **dotnet/skills (Official MS)** | — | `git clone https://github.com/dotnet/skills` | Official .NET team: perf investigations, MSBuild, debugging |
| **api-design** | 86 | `/plugin install api-design-principles@secondsky-claude-skills` | REST API design patterns |

### Infrastructure Plugins

| Plugin | Stars | Install | What it does |
|--------|-------|---------|-------------|
| **TerraShark** | 47 | `git clone https://github.com/LukasNiessen/terrashark ~/.claude/skills/terrashark` | Failure-mode-first Terraform (600 token activation) |
| **terraform-best-practices** | 29 | `npx skills add terramate-io/agent-skills` | 37 rules across 10 categories |
| **aws-serverless** | — | `git clone https://github.com/a-pavithraa/aws-serverless-skill ~/.claude/skills/aws-serverless` | Lambda, DynamoDB, API Gateway patterns |
| **aws-cost-ops** | 200 | `/plugin marketplace add zxkane/aws-skills` | Cost optimization + monitoring with MCP servers |
| **aws-cost-scanner** | — | `github.com/prajapatimehul/aws-cost-scanner` | 163 cost checks across 30+ AWS services |

### QA / Testing Plugins

| Plugin | Stars | Install | What it does |
|--------|-------|---------|-------------|
| **qaskills** | 83 | `npx @qaskills/cli add playwright-e2e` | 20+ skills: Playwright, Jest, security, a11y, k6 |
| **agentic-qe** | 264 | `npm install -g agentic-qe && aqe init --auto` | AI-powered test generation, coverage analysis, 74 skills |
| **playwright-qa** | — | `git clone https://github.com/sharmasundip/playwright-qa-skills ~/.claude/skills/playwright-qa` | Record browser → auto-generate Page Object Model tests |

### Data Plugins

| Plugin | Stars | Install | What it does |
|--------|-------|---------|-------------|
| **data-engineering-skills** | 65 | `git clone https://github.com/AltimateAI/data-engineering-skills && cp -r skills/* ~/.claude/skills/` | 7 dbt + 3 Snowflake skills |

### Large Collections (all roles)

| Plugin | Stars | Install | What it does |
|--------|-------|---------|-------------|
| **claude-skills** | 6,100 | `/plugin marketplace add alirezarezvani/claude-skills` | 205 skills: FE/BE, DB design, API review, a11y, Playwright |
| **claude-code-skills** | 694 | `/plugin marketplace add daymade/claude-code-skills` | 43 skills: UI designer, QA, i18n, skill creator |

---

## Configuration

### `dtf-config.json` (version 2)

Personal config, never committed. Created by `dtf install` or upgraded by `dtf configure`.

```json
{
  "version": 2,
  "user": {
    "name": "your-name",
    "githubUsername": "your-gh-user"
  },
  "role": "frontend-dev",
  "roleConfig": {
    "displayName": "Developer (Frontend)",
    "agents": ["frontend-dev", "architect", "pr-reviewer"],
    "skills": ["frontend-conventions", "tdd", "playwright-cli", "visual-development-workflow", "mermaid-diagram"]
  },
  "workflowSteps": [
    { "name": "ESLint check", "type": "automated", "command": "npm run lint", "when": "before-commit" },
    { "name": "Visual verification", "type": "reminder", "when": "before-pr" },
    { "name": "Screenshot capture", "type": "reminder", "when": "before-pr" },
    { "name": "My custom check", "type": "automated", "command": "npm run my-check", "when": "before-push" }
  ],
  "paths": {
    "monorepo": "~/Documents/MyProject",
    "worktreeParent": "~/Documents",
    "workflowRepo": "~/dream-team-flow"
  },
  "extraPaths": {},
  "terminal": "Alacritty"
}
```

### Version Migration

| Field | v1 | v2 |
|-------|----|----|
| `version` | 1 | 2 |
| `role` | — | Role key (e.g., `frontend-dev`) |
| `roleConfig` | — | Agents + skills for the role |
| `workflowSteps` | — | Custom workflow steps |

Run `dtf configure` to upgrade from v1 to v2.

---

## Company Config

Shared config (`company-config.json`) distributed by a team lead. Defines roles, services, and defaults.

```json
{
  "projectName": "MyProject",
  "repoUrl": "git@github.com:org/repo",
  "ticketPrefix": "PROJ",
  "jiraDomain": "company.atlassian.net",
  "services": {
    "ServiceA": "ServiceA",
    "ServiceB": "ServiceB"
  },
  "defaultPaths": {
    "monorepo": "~/Documents/MyProject",
    "worktreeParent": "~/Documents"
  },
  "roles": {
    "frontend-dev": {
      "description": "Developer (Frontend)",
      "agents": ["frontend-dev"],
      "skills": ["frontend-conventions", "tdd"],
      "suggestedExternalSkills": [
        { "name": "tailwind-v4-shadcn", "repo": "secondsky/claude-skills", "install": "/plugin marketplace add" }
      ]
    },
    "backend-dev": {
      "description": "Developer (Backend)",
      "agents": ["backend-dev"],
      "skills": ["backend-conventions", "tdd"],
      "suggestedExternalSkills": [
        { "name": "dotnet-skills", "repo": "Aaronontheweb/dotnet-skills", "install": "/plugin marketplace add" }
      ]
    },
    "infra": {
      "description": "Infrastructure / DevOps",
      "agents": ["infra-engineer"],
      "skills": ["infra-conventions"],
      "suggestedExternalSkills": [
        { "name": "terrashark", "repo": "LukasNiessen/terrashark", "install": "git clone" },
        { "name": "terraform-best-practices", "repo": "terramate-io/agent-skills", "install": "npx skills add" }
      ]
    },
    "tester": {
      "description": "QA / Tester",
      "agents": ["qa-tester"],
      "skills": ["testing-workflows", "playwright-cli"],
      "suggestedExternalSkills": [
        { "name": "qaskills", "repo": "PramodDutta/qaskills", "install": "npx @qaskills/cli" },
        { "name": "agentic-qe", "repo": "proffesor-for-testing/agentic-qe", "install": "npm install -g" }
      ]
    },
    "uat-tester": {
      "description": "UAT / QA Stakeholder",
      "agents": ["uat-tester"],
      "skills": ["uat-workflows"]
    },
    "data-engineer": {
      "description": "Data Engineer",
      "agents": ["data-engineer"],
      "skills": ["data-conventions"],
      "suggestedExternalSkills": [
        { "name": "data-engineering-skills", "repo": "AltimateAI/data-engineering-skills", "install": "git clone" }
      ]
    },
    "data-analyst": {
      "description": "Data Analyst",
      "agents": ["data-analyst"],
      "skills": ["data-analysis-workflows"]
    },
    "po": {
      "description": "Product Owner",
      "agents": ["po-analyst"],
      "skills": ["po-workflows"]
    },
    "sales": {
      "description": "Sales",
      "agents": ["sales-enablement"],
      "skills": ["presentation-workflows"]
    },
    "marketing": {
      "description": "Marketing",
      "agents": ["marketing-ops"],
      "skills": ["content-workflows"]
    },
    "customer-ops": {
      "description": "Customer Operations",
      "agents": ["customer-ops"],
      "skills": []
    }
  }
}
```

---

## Architecture

```
~/.claude/
├── agents/                        # 29 agents, organized by domain
│   ├── engineering/               #   Core development (7)
│   │   ├── frontend-dev.md
│   │   ├── backend-dev.md
│   │   ├── architect.md
│   │   ├── pr-reviewer.md
│   │   ├── api-designer.md
│   │   ├── performance-analyst.md
│   │   └── migration-planner.md
│   ├── data/                      #   Data & analytics (4)
│   │   ├── data-engineer.md
│   │   ├── data-analyst.md
│   │   ├── pipeline-builder.md
│   │   └── insights-reporter.md
│   ├── design/                    #   UX & UI (2)
│   │   ├── ui-designer.md
│   │   └── ux-researcher.md
│   ├── infrastructure/            #   DevOps & security (3)
│   │   ├── infra-engineer.md
│   │   ├── ci-cd-engineer.md
│   │   └── security-auditor.md
│   ├── marketing/                 #   Content & sales (4)
│   │   ├── marketing-ops.md
│   │   ├── sales-enablement.md
│   │   ├── content-creator.md
│   │   └── social-strategist.md
│   ├── operations/                #   Support & customer (2)
│   │   ├── customer-ops.md
│   │   └── support-responder.md
│   ├── product/                   #   Product management (3)
│   │   ├── po-analyst.md
│   │   ├── requirements-analyst.md
│   │   └── sprint-prioritizer.md
│   └── testing/                   #   QA & performance (4)
│       ├── qa-tester.md
│       ├── uat-tester.md
│       ├── api-tester.md
│       └── performance-benchmarker.md
├── skills/                        # Workflow guides (20+ skills)
│   ├── backend-conventions/
│   ├── content-workflows/
│   ├── data-analysis-workflows/
│   ├── data-conventions/
│   ├── frontend-conventions/
│   ├── infra-conventions/
│   ├── playwright-cli/
│   ├── po-workflows/
│   ├── presentation-workflows/
│   ├── testing-workflows/
│   ├── tdd/
│   ├── uat-workflows/
│   └── ...
├── commands/                      # Slash commands (/my-dream-team, etc.)
├── scripts/
│   └── dtf.sh                    # CLI: install, configure, steps, update, doctor
├── docs/
│   └── dtf-roles.md              # This file
├── dtf-config.json                # Personal config (role + steps + paths)
└── CLAUDE.md                      # Auto-generated project context
```

### How It Flows

```
dtf install / dtf configure
  ↓
Role selected → agents + skills + default steps assigned
  ↓
User customizes steps (remove, add, reorder)
  ↓
dtf-config.json written (version 2)
  ↓
During work sessions:
  on-start     → Show reminder checklist
  before-commit → Run automated checks, show reminders
  before-push   → Run automated checks, show reminders
  before-pr     → Run automated checks, show reminders
  after-pr      → Show reminder checklist
```
