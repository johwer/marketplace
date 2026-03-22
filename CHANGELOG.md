# Changelog

## 2026-03-22 — Docs Restructure, Security Scanning, Official Skills

### Added
- **7 role-specific guides** — `docs/roles/developer.md`, `infra.md`, `data.md`, `tester.md`, `product-owner.md`, `marketing-sales.md`, `customer-ops.md`
- **Workflow Steps guide** — `docs/workflow-steps.md` with setup, examples, defaults per role
- **Official Anthropic skills** — PDF, DOCX, PPTX, XLSX, Brand Guidelines, Skill Creator
- **12 marketing skills** — content-strategy, copywriting, email-sequence, seo-audit, ai-seo, social-content, sales-enablement, competitor-alternatives, copy-editing, lead-magnets, launch-strategy, marketing-ideas
- **Claude SEO** — 12 sub-skills: schema, E-E-A-T, Core Web Vitals
- **Context Optimization skill** — token cost reduction and KV-cache patterns
- **`config-scan.sh` security scanning** — now scans installed skills for injection patterns, checks company-config.json for credentials, audits permissions, reports allowlist for known-safe skills
- **Worktree Port Setup guide** — `docs/worktree-port-setup.md` for non-MedHelp repos
- **Auto-sync stats** — `/sync-config` auto-updates agent/skill/command counts in DTF README via markers
- **Jira tickets** — PLRS-2301 (useEffect style guide), PLRS-2302 (useEffect refactoring)

### Changed
- **README restructured as landing page** — "Pick Your Role. Build Your Flow." with role table linking to guides, 261→113 lines, zero repetition
- **`features.md` restructured as index** — features organized by role, each linking to its role guide
- **Core Features rewritten** — now shows value per role, not dev-centric feature list
- **`config-scan.sh` improvements** — skill allowlist for known-safe skills (Anthropic official, playwright-cli), `skipDangerousModePermissionPrompt` warning now includes mitigation guidance (deny rules), fenced code blocks excluded from pattern matching
- **`code-insights` skill** — React 19 aware (no useMemo/useCallback nudges), removed useEffect→use() nudge
- **Infra default steps** expanded — `terraform fmt`, `terraform validate`, WAF rules, monitoring/Slack, tags, GH Actions verification
- **`sync-config.sh`** — copies docs to DTF repo, auto-updates README stats via `<!-- STATS:START/END -->` markers

### Documented
- DTF README rewritten — landing page with role table, quick start, 4 differentiators, deep dives
- `docs/features.md` — index by role + shared features + deep dive links
- `docs/workflow-steps.md` — complete guide with terminal output examples, 5 custom step recipes
- `docs/roles/*.md` — 7 role guides with agents, skills, steps, plugins per role
- `docs/worktree-port-setup.md` — Vite/Docker/gitignore for any project
- DTF README Secure Setup — now describes config-based security + `config-scan.sh`

## 2026-03-21 — Role-Based Flows

### Added
- **12 roles** with tailored agent/skill/step configuration
  - Developer (Frontend, Backend, Fullstack), Data Engineer, Data Analyst, Infrastructure/DevOps, QA/Tester, UAT Stakeholder, Product Owner, Sales, Marketing, Customer Operations
- **`dtf configure`** — set or change role and workflow steps for existing users
- **`dtf steps`** — manage personal workflow steps (list, add, remove, reset)
- **16 new agents** organized into 8 domain subdirectories
  - `engineering/`: api-designer, performance-analyst, migration-planner
  - `data/`: pipeline-builder, insights-reporter
  - `design/`: ui-designer, ux-researcher
  - `infrastructure/`: ci-cd-engineer, security-auditor
  - `marketing/`: content-creator, social-strategist
  - `operations/`: support-responder
  - `product/`: requirements-analyst, sprint-prioritizer
  - `testing/`: api-tester, performance-benchmarker, uat-tester
- **Performance skills**: `frontend-performance`, `backend-performance`, `aws-performance`
- **Code insights skill**: opt-in refactoring nudges + DTO analysis with mermaid diagrams
- **Role-specific skills**: `po-workflows`, `testing-workflows`, `uat-workflows`, `data-analysis-workflows`, `presentation-workflows`, `content-workflows`, `infra-conventions`
- **`/infra-ticket`** command — Terraform workflow from Jira ticket to PR
- **`terraform-plan-summary.sh`** — structured plan output with add/change/destroy box
- **`verify-infra-workflows.sh`** — GH Actions + CODEOWNERS verification
- **`memory-health.sh`** — memory size check with suggestions (0 token cost)
- **`memory-hygiene` skill** — triggered at session start, not during active work
- **Company config with roles** — `company-config.json` now includes role definitions
- **Security skills** from Trail of Bits (3.8k stars): differential-review, insecure-defaults, static-analysis, supply-chain
- **Audit skills** from levnikolaevich (234 stars): 8 codebase auditors
- **`code-review-skill`** (159 stars) — React 19, TypeScript, perf, security guides
- **`claudekit`** (633 stars) — real-time hooks

### Changed
- Agents reorganized from flat directory to 8 domain subdirectories
- `dtf.sh` refactored: `declare -A` replaced with `case`-based functions for portability
- `ask()` and `ask_choice()` refactored from `eval` to `printf -v` for safety
- `create_symlinks()` updated to handle subdirectories
- `dtf-config.json` upgraded to version 2 (role, roleConfig, workflowSteps)
- Memory hygiene triggers moved from compact to session-start only
- Default workflow steps expanded per role (3-8 steps each)
- `strategic-compact` skill: removed memory check at compact (wrong timing)

### Documented
- `docs/dtf-roles.md` — complete role reference with personalization guide
- `docs/changelog-2026-03.md` — detailed changelog
- `docs/infra-onboarding-slack.md` — ready-to-send Slack guide for infra team
- Updated `docs/integrations.md` with role support and new commands
- Updated `CLAUDE.md` with 29 agents in 8 domains

## 2026-03 (earlier) — Foundation

- Initial DTF framework with `dtf install`, `update`, `doctor`, `contribute`
- 5 agents: architect, backend-dev, frontend-dev, data-engineer, pr-reviewer
- 8 skills: conventions, playwright, visual dev, mermaid, TDD, context modes, strategic compact
- 19 commands: Dream Team orchestration, PR review, ticket management
- 26 scripts: quality gates, analytics, workspace management
- Learning system: session retros → learnings → convention improvements
