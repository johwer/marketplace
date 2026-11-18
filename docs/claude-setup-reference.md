# Claude setup reference

Moved out of `~/.claude/CLAUDE.md` on 2026-11-18 so it is not loaded into every session. Read on demand.

## Custom Commands

**Dream Team & Workspace:**
- `/create-stories` — Full lifecycle orchestrator: takes one or more ticket IDs, sets up worktrees, launches Dream Teams, and handles cleanup when done
- `/workspace-launch` — Create a git worktree from a Jira ticket and spin up a Dream Team session
- `/workspace-cleanup` — Tear down a worktree, tmux session, and optionally delete the branch
- `/my-dream-team` — Orchestrate a multi-agent team to implement a Repo feature ticket. Flags: `--lite` (Claude decides agent usage), `--interview` (interview user before starting), `--no-worktree` (work in current dir), `--local` (no PR/push), `--resume`

**Code Review & Analysis:**
- `/review-pr` — Review a PR with line-level GitHub comments. Auto-detects PR from current branch, or specify a PR number. Fast (API-only), full (local worktree + builds with `--full`), or deep (4 parallel review agents + validation with `--deep`). Combine `--deep --full` for maximum depth.
- `/ticket-scout` — Batch sprint triage: scan tickets, assign story points 1-4, verdict (READY/REFINE/PUSH BACK/SKIP)
- `/ticket-refine` — Deep quality gate for a single ticket: push back on missing info, domain model impact, UX flows, conflicts. Depth scales with story points
- `/ticket-examples` — On-demand code variation examples: enumerate all enum/type combinations from existing codebase patterns for a ticket

**Design & Quality:**
- `/triage-issue` — Investigate a bug, find root cause, create a Jira ticket with a TDD fix plan
- `/design-an-interface` — Spawn 3 parallel agents with different constraints to generate radically different interface designs, then compare ("Design It Twice")
- `/request-refactor-plan` — Deep interview → codebase exploration → tiny-commit refactor plan → Jira ticket
- `/tdd` — Test-driven development loop: interface confirmation → red → green → refactor (Vitest or xUnit)
- `/improve-codebase-architecture` — Audit a service/module for agent-friendliness: confusing boundaries, shallow modules, tight coupling

**Learning & Optimization:**
- `/evolve` — Review detected usage patterns and promote them to skills, conventions, scripts, or memory

**Team & Config:**
- `/reviewers` — Add extra PR reviewers per category (frontend, backend, fullstack, infra, data) when the user asks. Default reviewers come from `.github/CODEOWNERS` when a PR goes ready.
- `/team-stats` — Dream Team leaderboard and history
- `/retro-proposals` — Analyze Dream Team learnings and route improvements to destination files
- `/pr-insights` — Surface review patterns from scraped PR data and propose convention changes
- `/scrape-jira-pushback` — Extract learnings from AI reviewer (Solomon) Jira comments to improve ticket reviewing
- `/sync-config` — Push all Claude config to GitHub (private + sanitized public repos). New commands/skills must be added to `PLUGIN_FILES`/`PLUGIN_DIRS` in `~/.claude/scripts/sync-config.sh` to be tracked
- `/acli-jira-cheatsheet` — Reference for ACLI Jira CLI commands

## Subagents (24 agents, 8 domains)

Agents organized by domain in `~/.claude/agents/`. Your role determines which load by default (see `dtf-roles.md`).

| Domain | Agents | Model |
|--------|--------|-------|
| `engineering/` | frontend-dev, backend-dev, architect, pr-reviewer, api-designer, performance-analyst, migration-planner | Sonnet (Opus for architect, pr-reviewer, migration-planner) |
| `data/` | data-engineer, data-analyst, insights-reporter | Sonnet |
| `design/` | ui-designer, ux-researcher | Sonnet |
| `infrastructure/` | infra-engineer, ci-cd-engineer, security-auditor | Sonnet (Opus for security-auditor) |
| `marketing/` | marketing-ops, sales-enablement | Sonnet |
| `operations/` | customer-ops, support-responder | Sonnet |
| `product/` | po-analyst, sprint-prioritizer | Opus for po-analyst, Sonnet for sprint-prioritizer |
| `testing/` | qa-tester, uat-tester, api-tester | Sonnet |

## Hooks

Active hooks in `~/.claude/settings.json`:
- **Tool usage logging** — Logs all tool calls for analytics (async, non-blocking)
- **Desktop notification** — macOS notification when Claude needs attention (idle, permission prompt)
- **Migration guard** — Warns when editing files in `migrations/` directories
- **Lock file guard** — Warns when editing lock files (package-lock.json, pnpm-lock.yaml, yarn.lock)
- **Auto-lint reminder** — Reminds to run CSharpier (.cs) or ESLint (.ts/.tsx) before committing
- **Teammate idle gate** — Prevents dev agents from going idle without notes, journal, and clean formatting (TeammateIdle hook)
- **Task completed gate** — Prevents dev agents from marking tasks complete without notes, journal, code changes, and passing type checks (TaskCompleted hook)

## Utility Scripts

- `bash ~/.claude/scripts/analyze-patterns.sh` — Analyze tool usage logs to detect recurring patterns (context gaps, struggle points, script candidates)
- `bash ~/.claude/scripts/cost-tracker.sh report` — Session cost report from tool usage data. Also: `session <id>`, `top-sessions`
- `bash ~/.claude/scripts/config-scan.sh` — Security/health scan of your Claude Code config (secrets, performance, hygiene). Grades A-F.

## Context Modes and Strategic Compaction

- Context modes: say "dev mode", "review mode" or "research mode". See `~/.claude/skills/context-modes/SKILL.md`.
- Strategic compaction: compact at phase boundaries, never mid-implementation. See `~/.claude/skills/strategic-compact/SKILL.md`. Works with the PreCompact hook.

## Token Optimization

- Thinking depth is set by the effort level, not a token budget
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: 50` — Compact earlier for better quality in long sessions
- 2026-11-18: user-only skills (marketing, SEO, ln-6xx coordinators, trailofbits, anthropic file-format duplicates, context-optimization, local-model-setup) carry `disable-model-invocation: true`, so their descriptions are not loaded; run them with `/name`. Backup: `~/.claude/backups/2026-11-18-before-token-trim.tgz`.

## Integrations

See `~/.claude/docs/integrations.md`.

| Integration | Status |
|-------------|--------|
| GitHub Actions (`@claude` in PRs) | Not installed — no `claude.yml` in the monorepo's workflows |
| Slack (`@Claude` in channels) | Documented — needs Claude Code on the Web + Pro/Max/Teams plan |
| Code intelligence plugin | Documented — run `/plugin` to browse marketplace |
