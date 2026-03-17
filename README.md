# Marketplace

Plugin marketplace for Claude Code workflows and tools. Any repo can use any command, agent, or script from this marketplace.

## Install

```bash
/plugin marketplace add johwer/marketplace
/plugin install claude-toolkit@marketplace
```

## What's Included

| Type | Contents |
|------|----------|
| **Commands (19)** | Dream Team orchestration, PR review, ticket scout/refine, retro analysis, workspace management, pattern evolution |
| **Agents (5)** | Architect (Opus), PR reviewer (Opus), backend/frontend/data devs (Sonnet) |
| **Skills (8)** | Backend/frontend/data conventions, Playwright CLI, visual development, mermaid diagrams, strategic compaction, context modes |
| **Scripts (26)** | Quality gates, Chrome queue, workspace lifecycle, CI polling, pattern analysis, cost tracking, config scanning |
| **Docs** | Dev workflow checklist, learning system, integration guides, instruction delivery |

### Commands

| Command | Purpose |
|---------|---------|
| `/create-stories` | Full lifecycle orchestrator — ticket to PR for one or more tickets |
| `/my-dream-team` | Multi-agent team implementation with `--lite`, `--local`, `--resume` flags |
| `/review-pr` | Line-level PR review. `--full` for local builds, `--deep` for multi-agent + validation |
| `/workspace-launch` | Create worktree from Jira ticket + spin up session |
| `/workspace-cleanup` | Tear down worktree, tmux, branch |
| `/ticket-scout` | Batch sprint triage with story point estimation |
| `/ticket-refine` | Deep quality gate for a single ticket |
| `/ticket-examples` | Code variation examples from codebase patterns |
| `/evolve` | Review tool usage patterns and promote to skills/conventions/scripts |
| `/reviewers` | Manage PR reviewer assignments per category |
| `/team-stats` | Dream Team leaderboard and history |
| `/retro-proposals` | Analyze learnings and route improvements |
| `/pr-insights` | Surface review patterns from scraped PR data |
| `/scrape-pr-history` | Extract structured learnings from merged PRs |
| `/scrape-jira-pushback` | Extract learnings from AI ticket reviews |
| `/sync-config` | Push config to GitHub (private + sanitized public) |

### Skills

| Skill | Purpose |
|-------|---------|
| `backend-conventions` | .NET microservices coding style |
| `frontend-conventions` | React/TypeScript coding style |
| `data-conventions` | Data engineering, EF Core, JSONB patterns |
| `playwright-cli` | Browser automation for testing and verification |
| `visual-development-workflow` | Write code, verify visually, iterate |
| `mermaid-diagram` | Diagram creation with syntax validation |
| `strategic-compact` | When/how to compact context at phase boundaries |
| `context-modes` | Dev/review/research mindsets with distinct priorities |

### Utility Scripts

| Script | Purpose |
|--------|---------|
| `quality-gate.sh` | Deterministic pre-push checks (formatting, linting, builds) |
| `analyze-patterns.sh` | Detect recurring patterns from tool usage logs |
| `cost-tracker.sh` | Session cost reports with relative units per tool |
| `config-scan.sh` | Security/health scan of Claude config (grades A-F) |
| `allocate-ports.sh` | Worktree port allocation (3100-3199) |
| `chrome-queue.sh` | Serialize Chrome access across concurrent worktrees |

## For Development Repos

This marketplace is repo-agnostic. Point any development repo at it:

```json
// your-repo/.claude/settings.json
{
  "extraKnownMarketplaces": {
    "marketplace": {
      "source": {
        "source": "github",
        "repo": "johwer/marketplace"
      }
    }
  }
}
```

## Companion Repos

- [dream-team-flow](https://github.com/johwer/dream-team-flow) — DTF framework documentation, improvement plan, and `dtf` CLI for company-specific setup
