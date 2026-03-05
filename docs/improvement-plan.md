# Dream Team Flow — Improvement Plan & Architecture Decisions

Living document tracking Claude Code platform features, how DTF relates to them, decisions made, and planned improvements. Updated after each documentation review.

**Last reviewed:** 2026-03-05 (Claude Code docs at code.claude.com/docs)

---

## Feature Comparison: DTF vs Native Claude Code

### Multi-Agent Orchestration

| Aspect | DTF (current) | Native Agent Teams |
|--------|--------------|-------------------|
| **How it works** | `/my-dream-team` spawns agents in separate tmux sessions, each in a worktree. Team lead coordinates via file-based messaging (`.dream-team/`) | Built-in `TeamCreate`/`SendMessage`/`TaskCreate` tools. Shared task list, direct messaging, split panes |
| **Communication** | File-based (journal, context.md, notes) | Native mailbox system, automatic message delivery |
| **Task tracking** | Manual via team lead prompt | Built-in task list with states (pending/in-progress/completed), dependencies, file-locking for claims |
| **Display** | Separate tmux windows (Alacritty) | In-process (Shift+Down to cycle) or split panes (tmux/iTerm2) |
| **Plan approval** | Architect reviews before devs start (prompt-based) | Native plan approval — teammate works read-only until lead approves |
| **Hooks** | `TeammateIdle` and `TaskCompleted` hooks (already using) | Same hooks, plus `SubagentStart`/`SubagentStop` |
| **Status** | Agent Teams is **experimental**, disabled by default | DTF is stable and battle-tested |

**Decision:** Keep DTF orchestration for now. Agent Teams is experimental with known limitations (no session resumption, task status lag, one team per session). DTF's file-based approach is more resilient and supports features Agent Teams doesn't (retros, journal, learnings, achievement tracking). **Revisit when Agent Teams exits experimental.**

**Future:** When Agent Teams stabilizes, evaluate migrating Dream Team to use native task list and messaging while keeping DTF's higher-level workflows (retros, quality gates, Jira integration).

---

### Visual Testing & Browser Automation

| Aspect | DTF (current) | Native Chrome Integration |
|--------|--------------|--------------------------|
| **How it works** | AppleScript → Chrome `execute javascript`. Complex coordinate mapping, JS click-by-index patterns | `claude --chrome` or `/chrome`. Claude controls Chrome directly via extension |
| **Capabilities** | Screenshots, JS execution, navigation, clicking by index | Click, type, read console, record GIFs, read DOM, navigate, interact with auth'd sites |
| **Reliability** | Fragile — Retina coordinate issues, permission errors, tab management | Native integration, handles tabs, modals, and login state |
| **Setup** | None (AppleScript built into macOS) | Requires Claude in Chrome extension (v1.0.36+) |
| **Recording** | Manual: screencapture + ffmpeg/Pillow | Built-in GIF recording |

**Decision:** Adopt Chrome Integration as primary. It solves every pain point documented in `visual-testing.md` (coordinates, permissions, tab management, GIF recording). AppleScript remains as fallback if Chrome extension is unavailable.

**Action items:**
- [ ] Test `claude --chrome` with the MedHelp frontend
- [ ] Update `dev-workflow-checklist.md` Section 1 to prefer Chrome integration
- [ ] Update `visual-testing.md` to document Chrome approach first, AppleScript as fallback
- [ ] Test GIF recording via Chrome vs current ffmpeg workflow

---

### Subagent Configuration

| Aspect | DTF (current) | Native Subagent Features |
|--------|--------------|--------------------------|
| **Agent definitions** | `.md` files in `~/.claude/agents/` with name, description, model | Same, plus: `memory`, `isolation`, `skills`, `hooks`, `maxTurns`, `background`, `permissionMode` fields |
| **Persistent memory** | Not used — agents start fresh each session | `memory: user` gives agents a persistent directory across sessions |
| **Worktree isolation** | Manual via `/workspace-launch` | `isolation: worktree` — automatic, auto-cleaned if no changes |
| **Skill injection** | Not used — agents read docs manually | `skills` field preloads skill content into agent context at startup |
| **Scoped hooks** | Global hooks in `settings.json` | Hooks in agent frontmatter run only while that agent is active |

**Decision:** Adopt `memory` for architect and pr-reviewer agents. These benefit most from accumulated knowledge (architecture patterns, review patterns). Don't add memory to dev agents — they should follow conventions, not learn their own.

**Action items:**
- [ ] Add `memory: user` to `architect.md` and `pr-reviewer.md`
- [ ] Add `skills` field to dev agents to preload coding conventions
- [ ] Evaluate `isolation: worktree` for PR review subagent
- [ ] Add scoped hooks to dev agents (e.g., block editing wrong service directory)

---

### Model Configuration

| Aspect | DTF (current) | Native Model Features |
|--------|--------------|----------------------|
| **Model per agent** | Set in agent frontmatter (`model: sonnet`, `model: opus`) | Same, plus `opusplan` alias |
| **Effort level** | `ultrathink` keyword in skill prompts (ticket-scout, retro-proposals) | Effort slider in `/model` (low/medium/high), `CLAUDE_CODE_EFFORT_LEVEL` env var |
| **Extended context** | Not used | `sonnet[1m]` — 1M token context for long sessions |
| **Subagent model override** | Per-agent in frontmatter | `CLAUDE_CODE_SUBAGENT_MODEL` env var for global override |

**Decision:** Added `ultrathink` to `/ticket-scout` and `/retro-proposals` (2026-03-05). Consider `opusplan` for architect — Opus for planning phase, Sonnet for implementation guidance. Test `sonnet[1m]` for long Dream Team sessions that hit compaction.

**Action items:**
- [ ] Test `opusplan` for architect agent
- [ ] Test `sonnet[1m]` for Dream Team lead session
- [ ] Document when to use which model in this file

---

### Skills System

| Aspect | DTF (current) | Native Skills Features |
|--------|--------------|----------------------|
| **Commands** | `.md` files in `~/.claude/commands/` | Same, plus `SKILL.md` in `.claude/skills/` directories |
| **Supporting files** | Not used | Skill directories can contain templates, examples, scripts alongside SKILL.md |
| **Dynamic context** | Not used | `!`command`` syntax runs shell commands before skill content is sent |
| **Forked context** | Not used | `context: fork` runs skill in isolated subagent |
| **Tool restriction** | Not used | `allowed-tools` limits what Claude can do during skill |

**Decision:** Current commands work fine. Adopt new features selectively:
- `!`command`` for `/ticket-scout` — pre-fetch Jira data instead of making Claude run it
- `context: fork` for heavy skills that pollute main context
- `allowed-tools` for read-only skills like `/review-pr`

**Action items:**
- [ ] Convert `/ticket-scout` to use `!`acli jira...`` for pre-fetching
- [ ] Add `context: fork` to `/ticket-scout` and `/retro-proposals`
- [ ] Add `allowed-tools` to `/review-pr` (read-only + gh CLI)
- [ ] Evaluate migrating commands/ to skills/ directory structure

---

### Plugin System

| Aspect | DTF (current) | Native Plugins |
|--------|--------------|----------------|
| **Distribution** | `dtf install` CLI — clones repo, symlinks into `~/.claude/` | `/plugin install` — built-in install, versioning, namespacing |
| **Updates** | `dtf update` — pull + verify symlinks | Plugins auto-update or manual update |
| **Namespacing** | Not namespaced — commands are global | Plugin skills get `plugin-name:skill-name` prefix |
| **Packaging** | Git repo with scripts | `.claude-plugin/plugin.json` manifest + directory structure |

**Decision:** Keep `dtf` CLI for now. It handles company-specific config, de-sanitization, and personal setup that plugins don't support. **Long-term goal:** Package the generic framework as a plugin, keep `dtf` for company-specific setup layer on top.

**Action items:**
- [ ] Evaluate plugin packaging for the public repo (generic framework)
- [ ] Keep dtf for company config layer (de-sanitization, Jira setup, service names)
- [ ] Consider hybrid: plugin for skills/agents, dtf for company config

---

### Built-in Skills

| Skill | What it does | DTF equivalent |
|-------|-------------|----------------|
| `/batch` | Parallel implementation across files, each in worktree with PR | No equivalent — useful for large migrations |
| `/simplify` | 3 parallel review agents (reuse, quality, efficiency) | `/review-pr` does similar but focused on PR diff |
| `/debug` | Reads session debug log for troubleshooting | No equivalent |
| `/claude-api` | API reference for building with Claude | Not relevant to DTF |

**Decision:** `/batch` is useful for large-scale changes that Dream Team doesn't handle well (e.g., rename across 200 files). `/simplify` could run after Dream Team implementation as a quality pass.

**Action items:**
- [ ] Test `/simplify` as a post-implementation step in Dream Team workflow
- [ ] Document `/batch` as available for large migrations in CLAUDE.md

---

### Hooks

| Aspect | DTF (current) | Available but not used |
|--------|--------------|----------------------|
| **Active hooks** | Tool logging, desktop notification, migration guard, lock file guard, auto-lint reminder, TeammateIdle gate, TaskCompleted gate | `SubagentStart`, `SubagentStop`, `WorktreeCreate`, `WorktreeRemove`, `PreToolUse` per-agent, HTTP hooks, prompt hooks |
| **Hook types** | Command hooks (shell scripts) | Also: HTTP hooks (POST to URL), prompt hooks (LLM evaluates) |

**Decision:** Current hooks are sufficient. HTTP hooks could be useful if we add a dashboard. Prompt hooks are interesting for nuanced validation (e.g., "is this commit message good enough?") but add latency and cost.

**Action items:**
- [ ] Consider `SubagentStart` hook to log when Dream Team agents spawn
- [ ] Evaluate prompt hooks for PR description quality validation

---

## Improvement Priority

### P0 — Do Soon
1. **Chrome Integration** — Test and adopt for visual testing. Biggest pain point reduction.
2. **Subagent `memory`** — Add to architect and pr-reviewer. Low effort, high compound value.

### P1 — Do Next
3. **Skill `context: fork`** — Add to `/ticket-scout` and `/retro-proposals` to avoid context pollution.
4. **`opusplan` for architect** — Test Opus planning + Sonnet execution split.
5. **Subagent `skills` preloading** — Inject coding conventions into dev agents.

### P2 — Evaluate Later
6. **Agent Teams migration** — Wait for experimental flag to be removed. Track progress.
7. **Plugin packaging** — Package generic DTF as a plugin when plugin ecosystem matures.
8. **`sonnet[1m]`** — Test for long Dream Team sessions.
9. **`/batch` and `/simplify`** — Test as supplementary tools.

### P3 — Monitor
10. **HTTP hooks** — If we build a Dream Team dashboard.
11. **Prompt hooks** — For nuanced validation.
12. **`WorktreeCreate`/`WorktreeRemove` hooks** — Custom worktree setup.

---

## Changelog

| Date | Change | Section |
|------|--------|---------|
| 2026-03-05 | Initial document created from full docs review | All |
| 2026-03-05 | Added `ultrathink` to ticket-scout and retro-proposals | Model Configuration |
| 2026-03-05 | Added PR comment triage to dev-workflow-checklist Section 3 | Not in this doc (checklist) |
| 2026-03-05 | Added EF migration guideline to repo docs (PR #2006) | Not in this doc (repo docs) |
