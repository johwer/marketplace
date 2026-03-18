# Dream Team Commands

Quick reference for all available slash commands.

---

## /my-dream-team {#my-dream-team}

Orchestrates a multi-agent team to implement a Repo feature ticket end-to-end — architecture analysis, backend/frontend implementation, PR review, testing, and GitHub review cycle.

**Flags:** `--lite` · `--interview` · `--local` · `--no-worktree` · `--resume`

---

## /create-stories {#create-stories}

Full lifecycle orchestrator with **parallel pre-hydration**. Takes one or more Jira ticket IDs, fetches and analyzes all tickets in parallel (scope, complexity, key files, conventions), then presents a recommendations table. The user chooses per ticket: **Dream Team** (Opus + agents), **Lite** (Sonnet solo, same quality gates), or **Just worktree** (no Claude session). Pre-hydrated context is written to `.dream-team/context.md` in each worktree so Dream Team/Lite sessions skip redundant exploration. Handles cleanup when each story is merged.

---

## /workspace-launch {#workspace-launch}

Creates a git worktree from a Jira ticket, allocates unique ports for Docker services and the Vite dev server, and opens a new terminal session ready for a Dream Team.

---

## /workspace-cleanup {#workspace-cleanup}

Tears down a workspace after a story is merged. Stops worktree Docker services, kills the tmux session, removes the git worktree and directory, and deletes the branch.

---

## /review-pr {#review-pr}

Reviews a pull request with line-level GitHub comments. Auto-detects the PR from the current branch, or specify a PR number. Runs in fast (API-only), full (local checkout + builds), or deep (4 parallel review agents + validation pass to eliminate false positives) mode.

**Flags:** `--full` · `--deep` · `--skip` · `--focus` · `--no-approve`

---

## /retro-proposals {#retro-proposals}

Analyzes Dream Team retro learnings across sessions, produces a health report, and routes improvements to destination files — agent prompts, repo docs, or personal config. Part of the [Learning System](../docs/learning-system.md).

---

## /scrape-pr-history {#scrape-pr-history}

Extracts structured review findings from merged PRs using parallel agents (waves of 30). Stores categorized findings (category, severity, resolution) in `pr-learnings.json`. Part of the [Learning System](../docs/learning-system.md).

---

## /pr-insights {#pr-insights}

Surfaces recurring review patterns from scraped PR data. Compares human vs AI reviewer effectiveness, identifies common code quality issues, and proposes convention improvements. Part of the [Learning System](../docs/learning-system.md).

---

## /team-stats {#team-stats}

Shows the Dream Team leaderboard and session history. Tracks per-agent achievements, review rounds, first-pass compile rates, and shoutouts across all recorded sessions.

---

## /ticket-scout {#ticket-scout}

Batch sprint triage. Scans upcoming Jira tickets, assigns story points (1-4), and gives each a verdict: READY / REFINE / PUSH BACK / SKIP. Cheap and fast — no codebase exploration. Use this first, then `/ticket-refine` for tickets that need deeper analysis.

---

## /ticket-refine {#ticket-refine}

Deep quality gate for a single ticket. Checks consistency (title vs description vs attachments), completeness, domain model impact, UX flow coverage, and generates concrete pushback posted as a Jira comment. Depth scales with story points — 1pt gets a quick sanity check, 4pt gets full analysis.

---

## /ticket-examples {#ticket-examples}

Generates concrete code variation examples from the codebase for a ticket. Enumerates all enum values, type combinations, data mappings, and rendering scenarios that need handling. Best used on-demand when existing patterns exist and completeness matters. Posts examples as a Jira comment.

---

## /evolve {#evolve}

Reviews patterns detected from tool usage analysis. Runs `analyze-patterns.sh` to find context gaps, struggle points, and script candidates from your tool-usage.csv log, then lets you promote valuable patterns to skills, conventions, scripts, or memory — or dismiss noise. Part of the [Learning System](../docs/learning-system.md).

---

## /reviewers {#reviewers}

Manages pre-configured PR reviewers per category (frontend, backend, fullstack, infra, data). Reviewers are assigned only after the user confirms in Phase 6 — never auto-assigned.

---

## /sync-config {#sync-config}

Pushes all Claude configuration files (commands, scripts, agents, settings) to the private `shared-claude-files` repo and the public `dream-team-flow` repo on GitHub.

---

## /acli-jira-cheatsheet {#acli-jira-cheatsheet}

Quick reference for ACLI Jira CLI commands — transition tickets, add comments, view workitems, and manage sprint state from the terminal.
