# Learning System — How Dream Team Flow Improves Over Time

Dream Team Flow has a built-in learning loop that captures insights from two sources and routes them to where they'll have the most impact. Every session contributes data, and periodic analysis turns that data into concrete improvements.

## Two Learning Paths

### Path 1: Session Retrospectives (Process Learnings)

**What it captures:** How agents coordinate, where instructions are unclear, what conventions agents discover during implementation.

**How it works:**

1. **Every Dream Team session ends with a retro** (Phase 6.75 in `/my-dream-team`). Each agent reflects on what went well, what was confusing, and what conventions they discovered. The team lead synthesizes these into four categories with destination hints. Note: sessions launched via `/create-stories` benefit from parallel pre-hydration — context is pre-analyzed before the session starts, so Phase 1 focuses on validation rather than full exploration.

2. **Learnings accumulate** in `dream-team-learnings.md` (per-project memory). Each session appends an entry with instruction improvements, convention discoveries, doc gaps, and process notes.

3. **Periodically, run `/retro-proposals`** to analyze accumulated learnings, produce a health report, and route improvements to the correct destination files (agent prompts, repo docs, personal config).

**Commands:**
| Command | Purpose |
|---------|---------|
| `/my-dream-team` (Phase 6.75) | Captures retro learnings at end of each session |
| `/retro-proposals` | Analyzes learnings, proposes and routes improvements |

**Data flow:**
```
Session retro → dream-team-learnings.md → /retro-proposals → destination files
                dream-team-history.json ↗
```

### Path 2: PR Review Mining (Code Quality Learnings)

**What it captures:** What reviewers (human and AI) flag most often in pull requests — recurring patterns, common mistakes, code quality trends.

**How it works:**

1. **Run `/scrape-pr-history`** to extract structured review findings from merged PRs. This launches parallel agents (waves of 30) that analyze each PR's comments, reviews, and resolution status.

2. **Findings accumulate** in `pr-learnings.json` (per-project memory). Each PR gets a structured object with categorized findings, reviewer info, severity, and resolution status.

3. **Run `/pr-insights`** to analyze the accumulated PR data, surface recurring patterns, compare human vs AI reviewer effectiveness, and propose convention improvements.

**Commands:**
| Command | Purpose |
|---------|---------|
| `/scrape-pr-history` | Collects structured review data from merged PRs |
| `/pr-insights` | Analyzes PR data, surfaces patterns, proposes improvements |

**Data flow:**
```
GitHub PR reviews → /scrape-pr-history → pr-learnings.json → /pr-insights → destination files
```

## How Scraping Works: Waves and Agents

`/scrape-pr-history` processes PRs in parallel **waves** to maximize throughput while staying within context limits:

- **Wave size:** 30 PRs per wave
- **Agent per PR:** Each PR gets its own lightweight Haiku agent that fetches PR metadata, review comments, and review status from the GitHub API
- **Structured extraction:** Each agent returns a JSON object with categorized findings (i18n, naming, pattern, types, security, performance, etc.), severity levels (must-fix, suggestion, question, nitpick), and resolution status
- **Checkpoint/resume:** A checkpoint file tracks progress so the process can resume across sessions if context runs out
- **Deduplication:** Already-processed PRs are skipped automatically

**What the agents look for:**
- Review comments from ALL reviewers (human and AI bots like Gemini, Copilot, Claude)
- The **category** of each finding (what kind of issue)
- The **severity** (must-fix, suggestion, question, nitpick)
- Whether the issue was **resolved** (thread marked resolved or follow-up commit addresses it)
- The **fix pattern** (how it was fixed, if resolved)
- Whether the PR was authored by a Dream Team session

## Shared Routing System

Both paths feed into the same **Learning Router** (defined in `/retro-proposals`). This routes improvements to the correct destination:

| Destination | What goes there |
|-------------|----------------|
| `dream-team` | Agent coordination, timing, prompting improvements |
| `agent:<name>` | Standalone agent behavior outside Dream Team |
| `skill:<name>` | Skill/command workflow improvements |
| `repo-docs` | Coding conventions, style guides, API patterns |
| `agents-md:<path>` | Service-specific operational gotchas |
| `project-claude` | Monorepo structure, quick-start info |
| `memory` | General knowledge, notes for future reference |

Improvements split into two tracks:
- **Direct apply** (personal config): Applied immediately to `~/.claude/` files
- **Ticket + PR** (shared repo): Grouped into a Jira ticket and PR for team review

## Knowledge Layers — What Agents Actually See

Not all documentation is automatically loaded. Understanding what agents see on startup prevents knowledge loss and duplication.

### Auto-loaded (always visible to agents):
| Source | Scope | When loaded |
|--------|-------|-------------|
| `~/.claude/CLAUDE.md` | Global config, commands, integrations | Every session |
| `MEMORY.md` (auto-memory) | Project-scoped knowledge | Every session in project |
| `CLAUDE.md` in working directory | Repo/worktree conventions | Every session in that directory |

### NOT auto-loaded (agent must explicitly read):
| Source | Content |
|--------|---------|
| `~/.claude/docs/dev-workflow-checklist.md` | Hard gates, quality checks, PR resolution |
| `~/.claude/docs/learning-system.md` | This file |
| `visual-testing.md`, `medhelp-navigation.md` | Detailed operational guides in memory folder |
| `docs/*.md` in repo | Coding style, API conventions, testing guidelines |

### The duplication problem

Agents that don't see the checklist will rediscover its content and save it to MEMORY.md, creating duplicates. Removing duplicates from MEMORY.md causes agents to lose knowledge they need.

### Solution: MEMORY.md as cheat sheet

MEMORY.md serves two roles:
1. **Cheat sheet** — Essential one-liners that summarize key rules from the checklist and repo docs. Agents see these on startup without reading anything else.
2. **Index** — Links to detailed references (`visual-testing.md`, `dev-workflow-checklist.md`, repo docs) for when agents need the full picture.

Rules for MEMORY.md content:
- **Do** keep essential operational one-liners (i18n, PR workflow, pre-push gates)
- **Do** mark them as summaries so agents don't expand them into full paragraphs
- **Do** link to the detailed source for each topic
- **Don't** duplicate full procedures — keep it to one line per topic
- **Don't** remove a one-liner just because the detail exists elsewhere — agents may never read "elsewhere"

This accepts controlled overlap between MEMORY.md and the checklist. The checklist is the source of truth; MEMORY.md is the delivery mechanism.

## Privacy & Anonymization

The learning system stores reviewer names (GitHub logins) in `pr-learnings.json` for accurate analysis. When sharing results externally:

- `/pr-insights` supports anonymized output — human reviewers become "Human-1", "Human-2", etc.
- AI reviewer names (Gemini, Copilot, Claude) can also be anonymized to "AI-1", "AI-2"
- The focus is on **patterns**, not individuals — what categories of issues appear most, not who makes the most mistakes

## Getting Started

```bash
# 1. Scrape PR history (one-time, then periodic updates)
/scrape-pr-history --limit 200

# 2. Analyze PR patterns
/pr-insights

# 3. After several Dream Team sessions, analyze retro learnings
/retro-proposals

# 4. Both commands route improvements to the same destination files
```

## Tips

- Run `/scrape-pr-history` weekly to keep PR data fresh — already-stored PRs are skipped
- `/pr-insights` gets more useful with more data: 50+ PRs for initial patterns, 200+ for strong signals
- `/retro-proposals` gets more useful after 3+ Dream Team sessions
- Use `--dream-team-only` on `/pr-insights` to measure agent code quality over time
- Pair both: retros capture **process** learnings, PR insights capture **code quality** learnings
