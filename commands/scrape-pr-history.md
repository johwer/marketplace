# Scrape PR History — Extract Structured Learnings from Merged PRs

Extract review findings from merged GitHub PRs using parallel Haiku agents and store them as structured learnings.

## Config

- **Repo**: `RepoAB/Repo`
- **Storage**: `~/.claude/projects/-Users-username-Documents-Repo/memory/pr-learnings.json`
- **Batch size**: 30 agents in parallel
- **Default PRs to fetch**: 100

## Invocation

```
/scrape-pr-history [--limit N] [--force]
```

- `--limit N` — Override default PR count (default: 100)
- `--force` — Re-process already-stored PRs

## Step 1: Load Existing Data

Read `~/.claude/projects/-Users-username-Documents-Repo/memory/pr-learnings.json` if it exists.

Extract the list of already-processed PR numbers. These will be skipped unless `--force` is passed.

If the file doesn't exist, start with an empty array `[]`.

## Step 2: Fetch Merged PRs

```bash
gh pr list --repo RepoAB/Repo --state merged --limit <N> \
  --json number,title,headRefName,mergedAt,author \
  --jq 'sort_by(.mergedAt) | reverse'
```

Filter out PR numbers already in the stored data (unless `--force`).

Extract the ticket ID from branch name or title using this priority:
1. Branch name: find `PROJ-\d+` pattern (case-insensitive)
2. PR title: find `PROJ-\d+` pattern
3. If neither: `ticket: null`

## Step 3: Fan Out — 30 Haiku Agents in Parallel

Split the unprocessed PRs into batches. Launch up to 30 Task agents simultaneously using `subagent_type: "general-purpose"` and `model: "haiku"`.

Give each agent **one PR** to analyze. Pass the PR number and repo in the prompt. See the **Agent Prompt** section below.

Collect all results. If an agent fails or returns malformed JSON, log a warning and skip that PR (don't crash the whole batch).

For large backlogs (>30 unprocessed), run in waves of 30 until all are done.

## Agent Prompt (per PR)

Use this exact prompt structure for each Haiku agent. Replace `{PR_NUMBER}` with the actual number.

```
You are extracting structured review findings from a merged GitHub PR.

PR: {PR_NUMBER}
Repo: RepoAB/Repo

Run these commands in sequence:

1. gh pr view {PR_NUMBER} --repo RepoAB/Repo --json number,title,headRefName,mergedAt,author,body
2. gh api repos/RepoAB/Repo/pulls/{PR_NUMBER}/comments
3. gh api repos/RepoAB/Repo/pulls/{PR_NUMBER}/reviews

Then return ONLY a JSON object (no markdown, no explanation) in this exact shape:

{
  "pr": {PR_NUMBER},
  "ticket": "PROJ-XXXX or null",
  "title": "PR title",
  "merged_at": "ISO date",
  "author": "github login",
  "findings": [
    {
      "reviewer": "github login",
      "reviewer_is_bot": true or false,
      "file": "path/to/file.tsx or null",
      "comment_summary": "one sentence: what the reviewer flagged",
      "category": "one of: i18n | naming | pattern | missing-test | security | performance | accessibility | api-contract | error-handling | types | styling | architecture | other",
      "severity": "must-fix | suggestion | question | nitpick",
      "was_resolved": true or false,
      "fix_pattern": "one sentence: how it was fixed, or null if not resolved"
    }
  ],
  "total_comments": N,
  "human_reviewer_count": N,
  "has_dream_team_markers": true or false
}

Rules:
- Only include findings from actual review comments (not general PR description text)
- Include findings from ALL reviewers: humans AND bots (Gemini, Claude, etc.) — mark reviewer_is_bot accordingly
- `was_resolved` = true if the comment thread is marked resolved OR a follow-up commit clearly addresses it
- `has_dream_team_markers` = true if the PR body or branch name suggests it was a Dream Team session (branch named exactly PROJ-XXXX, or body mentions "Dream Team" or "my-dream-team")
- `severity` = your best judgment: must-fix (blocking approval), suggestion (improvement), question (clarification), nitpick (style/minor)
- If there are no review comments, return findings: []
- Return ONLY the JSON object, nothing else
```

## Step 4: Merge Results

After each batch of agents completes:

1. Read the current `pr-learnings.json` (it may have been updated by a previous wave)
2. Append the new PR objects
3. Write back to `pr-learnings.json`

Keep the array sorted by `merged_at` descending (newest first).

## Step 5: Print Summary

After all batches complete, print:

```
## PR Scrape Complete

- PRs processed: N
- PRs skipped (already stored): N
- Total findings extracted: N
- Human reviewers found: N unique logins
- Bot reviewers found: N unique logins

### Top Categories
1. pattern — N findings
2. naming — N findings
3. i18n — N findings
...

### Dream Team PRs
- N PRs had Dream Team markers
- N findings from Dream Team PRs

### Already-Stored
Total in pr-learnings.json: N PRs
Date range: [oldest] → [newest]
```

Then ask the user:
- "Run `/pr-insights` to surface patterns from these findings?"
- "Filter to Dream Team PRs only?"
- "Run `/retro-proposals` to route learnings to destination files?"

## Storage Format

`pr-learnings.json` is an array of PR objects:

```json
[
  {
    "pr": 1838,
    "ticket": "PROJ-1577",
    "title": "PROJ-1577: Password reset initialization endpoint",
    "merged_at": "2026-02-27T15:15:28Z",
    "author": "cachpachios",
    "findings": [
      {
        "reviewer": "gemini-code-assist[bot]",
        "reviewer_is_bot": true,
        "file": "docker-compose.yml",
        "comment_summary": "TODO placeholder in PasswordReset__PasswordResetUrl should be replaced before production deploy",
        "category": "other",
        "severity": "must-fix",
        "was_resolved": false,
        "fix_pattern": null
      }
    ],
    "total_comments": 5,
    "human_reviewer_count": 2,
    "has_dream_team_markers": false
  }
]
```

## Tips

- Run periodically (e.g., weekly) to keep learnings fresh — already-stored PRs are skipped automatically
- Haiku agents handle diffs well up to ~50k tokens; very large PRs may be trimmed by the model
- Bot findings (Gemini, Claude) are valuable — they reveal what automated review catches vs. misses
- `has_dream_team_markers` lets you filter to Dream Team-authored PRs to measure agent quality over time
- After scraping, use `/pr-insights` to surface the most common patterns across all findings
- This command is part of the [Learning System](../docs/learning-system.md)
