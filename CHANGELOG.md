# Changelog

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
