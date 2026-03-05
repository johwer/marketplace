# PR Insights — Surface Review Patterns from Scraped PR Data

Analyze the structured review findings in `pr-learnings.json` (collected by `/scrape-pr-history`) to surface recurring patterns, identify what reviewers (human and AI) catch most often, and propose convention improvements.

> This command is part of the [Learning System](../docs/learning-system.md). It does for PR review data what `/retro-proposals` does for Dream Team session retros.

## Data Source

Read `~/.claude/projects/-Users-johanwergelius-Documents-MedHelp/memory/pr-learnings.json`.

If the file doesn't exist or has fewer than 10 PRs, tell the user to run `/scrape-pr-history` first.

## Invocation

```
/pr-insights [--dream-team-only] [--category <cat>] [--min-occurrences N]
```

- `--dream-team-only` — Only analyze PRs where `has_dream_team_markers` is true
- `--category <cat>` — Focus on a single category (e.g., `i18n`, `pattern`, `types`)
- `--min-occurrences N` — Only show patterns that appear N+ times (default: 2)

## Analysis

### Step 1: Load & Aggregate

Load all PR objects from `pr-learnings.json`. Compute:

- Total PRs analyzed
- Date range (oldest → newest `merged_at`)
- Total findings
- PRs with zero findings (no review comments)
- Dream Team PRs vs non-Dream-Team PRs

### Step 2: Category Breakdown

Group all findings by `category` and count:

```
### Finding Categories (sorted by frequency)

| Category | Count | % of Total | Human | AI | Must-Fix | Resolved |
|----------|-------|------------|-------|-----|----------|----------|
| pattern  | 45    | 22%        | 12    | 33  | 8        | 30       |
| types    | 38    | 18%        | 5     | 33  | 15       | 25       |
| ...      |       |            |       |     |          |          |
```

### Step 3: Reviewer Analysis

Classify reviewers as **human** or **AI** based on `reviewer_is_bot`. Aggregate:

```
### Reviewer Breakdown

| Type | Reviewers | Total Findings | Must-Fix | Resolution Rate |
|------|-----------|----------------|----------|-----------------|
| AI   | N unique  | N              | N        | N%              |
| Human| N unique  | N              | N        | N%              |

### AI Reviewer Comparison
| Reviewer | Findings | Must-Fix | Categories (top 3) |
|----------|----------|----------|--------------------|
| AI-1     | N        | N        | pattern, types, ... |
| AI-2     | N        | N        | security, types, ...|

### Human Reviewer Activity
| Reviewer | Reviews | Findings | Must-Fix | Top Category |
|----------|---------|----------|----------|-------------|
| Human-1  | N PRs   | N        | N        | pattern     |
| Human-2  | N PRs   | N        | N        | naming      |
```

> **Privacy note:** When presenting to the user, show reviewer names. If the user asks for anonymized output (for sharing), replace human names with "Human-1", "Human-2" etc. and AI reviewer names with "AI-1", "AI-2" etc.

### Step 4: Recurring Patterns

Find comment summaries that describe the **same issue** across multiple PRs. Group by semantic similarity (same category + similar file paths or comment text):

```
### Recurring Review Patterns (appearing 2+ times)

1. **[category] Pattern description** — N occurrences across N PRs
   - Severity: mostly [severity]
   - Resolution rate: N%
   - Example files: [list]
   - Fix pattern: [common fix if resolved]
   - **Proposed action:** [specific convention to add or doc to update]

2. ...
```

### Step 5: Dream Team vs Manual Comparison

If both Dream Team and non-Dream-Team PRs exist:

```
### Dream Team Quality Comparison

|                    | Dream Team PRs | Manual PRs |
|--------------------|---------------|------------|
| PRs analyzed       | N             | N          |
| Avg findings/PR    | N             | N          |
| Must-fix rate      | N%            | N%         |
| Resolution rate    | N%            | N%         |
| Top category       | X             | Y          |
```

### Step 6: Proposed Convention Changes

For each recurring pattern (Step 4) with 3+ occurrences, propose a concrete action using the same destination registry as `/retro-proposals`:

```
### Proposed Improvements

| # | Pattern | Occurrences | Destination | Proposed Change |
|---|---------|-------------|-------------|-----------------|
| 1 | font-sans on individual elements | 5 | repo-docs:docs/TAILWIND_CONVENTIONS.md | Add rule: never apply font-sans to individual elements |
| 2 | Missing i18n for labels | 4 | repo-docs:docs/INTERNATIONALIZATION.md | Add checklist for new component i18n |
| 3 | Unused imports after refactor | 8 | dream-team | Add post-refactor cleanup step to agent prompts |
```

## Output Report

Print the full report:

```
## PR Review Insights

### Overview
- PRs analyzed: N (DATE → DATE)
- Total findings: N
- Dream Team PRs: N (N findings)

### Finding Categories
[Step 2 table]

### Reviewer Breakdown
[Step 3 tables]

### Recurring Patterns
[Step 4 list]

### Dream Team Quality
[Step 5 table, if applicable]

### Proposed Improvements
[Step 6 table]
```

## Actions

After the report, ask the user:

- "Route proposed improvements" — Use the same Learning Router from `/retro-proposals` to apply changes (direct apply for personal config, ticket+PR for repo docs)
- "Export anonymized report" — Generate a shareable version with anonymized reviewer names
- "Focus on [category]" — Re-run analysis for a single category in depth
- "Compare Dream Team vs manual" — Drill into the quality comparison
- "Skip"

## Tips

- Run after `/scrape-pr-history` to analyze fresh data
- More PRs = better pattern detection. 50+ PRs gives meaningful results, 200+ gives strong signals
- Use `--dream-team-only` to measure agent-authored code quality over time
- The proposed improvements feed into the same Learning Router as `/retro-proposals` — they end up in the same destination files
- Pair with `/retro-proposals` for a complete picture: retros capture *process* learnings, PR insights capture *code quality* learnings
