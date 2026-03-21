# Instruction Delivery Mechanisms

How Claude Code receives instructions, conventions, and context. Each mechanism has a specific role — use the right one for the job to avoid duplication and drift.

## Overview

| Mechanism | Loading | Scope | Size | Best For |
|-----------|---------|-------|------|----------|
| **CLAUDE.md / AGENTS.md** | Auto — loaded when Claude enters the directory | Directory-specific | Small (loaded into every prompt) | Quick-reference commands, key file paths, project structure |
| **Skills** | Explicit — invoked via Skill tool or referenced in agent prompts | Reusable across any context | Can be large (loaded on demand) | Heavy conventions, reusable workflows, tool-specific guides |
| **Commands** | User-invoked — `/command-name` slash commands | Session-scoped orchestration | Large (full workflow prompts) | Multi-step processes, agent orchestration, user-facing workflows |
| **Agents** | Spawned — via Agent tool with specific prompts | Task-scoped subprocess | Medium (agent definition + spawn prompt) | Specialized roles, parallel work, isolated context |
| **Hooks** | Automatic — triggered by events (tool calls, idle, task completion) | Event-driven enforcement | Tiny (shell scripts) | Quality gates, formatting reminders, guardrails |
| **Memory** | Auto — always loaded into context | Cross-session persistence | Small (truncated at 200 lines) | Learnings, preferences, stable patterns confirmed over time |
| **Plugins** | Installed — marketplace plugins add skills/commands/agents | Shared community tools | Varies | Third-party integrations, community workflows |

## When to Use What

### CLAUDE.md / AGENTS.md — Directory Context

**Auto-loaded** by Claude Code when it enters a directory. Zero-effort context — you don't need to remember to invoke it.

**Use for:**
- Project structure and quick-start commands
- Key file paths and references to full docs
- Service-specific gotchas ("this service uses Dapper, not EF Core")
- Pointers to skills/docs for details ("use `backend-conventions` skill for full style guide")

**Don't use for:**
- Full coding conventions (too large — clutters every prompt)
- Step-by-step workflows (use commands instead)
- Enforcement rules (use hooks instead)

**Repo repo pattern:** `CLAUDE.md` is a symlink to `AGENTS.md` — one file serves both Claude Code (reads `CLAUDE.md`) and other AI tools (read `AGENTS.md`). Always edit `AGENTS.md`.

**Keep it small.** Every line in CLAUDE.md is loaded into every prompt when working in that directory. Bloated CLAUDE.md wastes context on irrelevant information.

### Skills — On-Demand Knowledge

**Explicitly invoked** via the Skill tool or referenced in agent prompts. Loaded only when needed.

**Use for:**
- Heavy convention docs (coding style, component library, API patterns)
- Tool-specific guides (Playwright CLI, mermaid diagrams)
- Reusable workflows (visual development, code generation)
- Knowledge that multiple agents/commands need but shouldn't be in every prompt

**Don't use for:**
- Quick-reference info that agents need constantly (use CLAUDE.md)
- User-facing workflows with multiple phases (use commands)
- Enforcement (use hooks)

**DTF skills:**
| Skill | Purpose |
|-------|---------|
| `frontend-conventions` | Full frontend coding style for the monorepo |
| `backend-conventions` | Full backend coding style for the monorepo |
| `data-conventions` | Data engineering conventions for the monorepo |
| `playwright-cli` | Browser automation reference |
| `mermaid-diagram` | Diagram creation with syntax validation |
| `visual-development-workflow` | Write code → verify visually → iterate |
| `strategic-compact` | When/how to compact context at phase boundaries |
| `context-modes` | Dev/review/research mindsets with distinct priorities |

**Reliability advantage:** Skills are explicitly invoked, so they always load. CLAUDE.md auto-loading can be inconsistent depending on working directory context.

### Commands — User-Facing Workflows

**User-invoked** via `/command-name`. Expands into a full prompt that orchestrates multi-step processes.

**Use for:**
- Multi-phase workflows (`/my-dream-team`, `/create-stories`)
- User-interactive processes (`/review-pr`, `/ticket-scout`)
- Orchestration that spawns agents, creates PRs, manages Jira
- Anything the user triggers and expects a structured outcome from

**Don't use for:**
- Conventions or reference docs (use skills)
- Background enforcement (use hooks)
- Lightweight context (use CLAUDE.md)

**DTF commands:** `/my-dream-team`, `/create-stories`, `/review-pr`, `/workspace-launch`, `/workspace-cleanup`, `/ticket-scout`, `/ticket-refine`, `/ticket-examples`, `/reviewers`, `/team-stats`, `/retro-proposals`, `/evolve`, `/sync-config`, and more. See `/commands` for the full list.

### Agents — Specialized Subprocesses

**Spawned** via the Agent tool. Each gets its own context window and role.

**Use for:**
- Specialized roles (architect, backend dev, frontend dev, reviewer)
- Parallel work (backend + frontend simultaneously)
- Isolated context (heavy codebase exploration without polluting main context)
- Tasks that benefit from a specific model tier (opus for architecture, sonnet for implementation)

**Don't use for:**
- Simple tasks you can do directly (use CLAUDE.md + skills)
- Convention docs (use skills — agents read skills, not the other way around)
- One-off enforcement (use hooks)

**DTF agents:**
| Agent | Model | Role |
|-------|-------|------|
| `architect` | Opus | Architecture analysis, conventions summaries, implementation plans |
| `backend-dev` | Sonnet | .NET backend implementation |
| `frontend-dev` | Sonnet | React/TypeScript frontend implementation |
| `pr-reviewer` | Opus | Code review with categorized feedback |
| `data-engineer` | Sonnet | Data mapping, EF Core migrations, pipelines |

### Hooks — Automated Enforcement

**Event-driven** shell scripts triggered by Claude Code events (tool calls, idle, task completion).

**Use for:**
- Quality gates that must never be skipped (formatting, type checks)
- Guardrails (warn on migration edits, lock file changes)
- Automated reminders (lint before commit)
- Notifications (desktop alert when Claude needs attention)
- Agent discipline (idle gate, task completion gate)

**Don't use for:**
- Conventions (use skills — hooks enforce, skills inform)
- Workflows (use commands)
- Context (use CLAUDE.md or memory)

**Key property:** Hooks are deterministic and non-negotiable. An agent can ignore a CLAUDE.md instruction, but it can't bypass a hook that blocks tool execution.

### Memory — Cross-Session Persistence

**Auto-loaded** from `~/.claude/projects/*/memory/MEMORY.md` (first 200 lines). Persists across conversations.

**Use for:**
- Stable patterns confirmed across multiple sessions
- Project-specific preferences and decisions
- Solutions to recurring problems
- History and metrics (dream-team-history.json)

**Don't use for:**
- Conventions that belong in docs (use skills or repo docs)
- Session-specific context (temporary, will be stale next session)
- Anything that duplicates CLAUDE.md or repo docs

### Plugins — Community Extensions

**Installed** from marketplaces. Add skills, commands, agents, and hooks from the community.

**Use for:**
- Third-party tool integrations
- Community-maintained workflows
- Shared patterns across teams/projects

**DTF marketplaces:** `claude-plugins-official`, `anthropic-agent-skills`

## Architecture Decision: Don't Duplicate, Delegate

Each mechanism has one job. When you need to add new instructions:

1. **Is it directory-specific context?** → `AGENTS.md` (small, pointer-style)
2. **Is it a full convention or reference doc?** → Skill (loaded on demand)
3. **Is it a user-facing workflow?** → Command (slash command)
4. **Is it a specialized role for parallel work?** → Agent definition
5. **Is it a rule that must be enforced?** → Hook (can't be ignored)
6. **Is it a cross-session learning?** → Memory
7. **Is it a shared community tool?** → Plugin

**Anti-pattern:** Putting full conventions in CLAUDE.md. This wastes context budget on every prompt. Instead, CLAUDE.md should say "use `backend-conventions` skill for full style guide" and the skill carries the heavy content.

**Anti-pattern:** Duplicating the same rule in CLAUDE.md, a skill, AND a hook. Instead: the skill *documents* the rule, the hook *enforces* it, and CLAUDE.md *points* to both.

## Flow: How Instructions Reach an Agent

```
User types /my-dream-team
    │
    ├─ Command loads (my-dream-team.md) ─── orchestration workflow
    │
    ├─ CLAUDE.md auto-loaded ─── project context, key paths
    │
    ├─ Memory auto-loaded ─── past learnings, preferences
    │
    ├─ Team Lead spawns Agent (e.g., Kenji)
    │   ├─ Agent definition (backend-dev.md) ─── role & capabilities
    │   ├─ Spawn prompt ─── task-specific instructions
    │   ├─ CLAUDE.md from working directory ─── project context
    │   └─ Agent reads Skill (backend-conventions) ─── full conventions
    │
    └─ Hooks fire on tool calls ─── formatting, guards, gates
```
