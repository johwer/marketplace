# Scrape Jira Pushback — Extract Learnings from AI Ticket Reviews

Extract structured learnings from AI reviewer comments on Jira tickets. Analyzes how the AI reviewer pushes back, what it catches, what it misses, and how the team responds — to improve both `/ticket-refine` and the AI reviewer itself.

## Config

Read team configuration from `~/.claude/team-profiles.json`. If the file doesn't exist, ask the user to set it up (see **Setup for New Teams** below).

From the config, extract:
- `ai_reviewer.email` — the AI reviewer's Jira email
- `ai_reviewer.display_name` — used in output
- `project` — Jira project key
- `ticket_prefix` — for JQL queries
- `tech_leads` — list of names considered "tech lead" for the "has tech lead commented" check
- `author_profiles` — known ticket authors (used for writing quality assessment)

**Storage** (always per-project memory):
- `jira-pushback-learnings.json` — structured findings
- `jira-pushback-checkpoint.json` — progress tracker

**Batch size**: 10 agents in parallel

## Invocation

```
/scrape-jira-pushback [--limit N] [--force] [--ticket PREFIX-XXXX]
```

- `--limit N` — Override default ticket count (default: all found)
- `--force` — Re-process already-stored tickets
- `--ticket PREFIX-XXXX` — Analyze a single ticket only (useful for testing)

## Setup for New Teams

If `~/.claude/team-profiles.json` doesn't exist, create it interactively by asking:

1. "What's your Jira project key?" (e.g., `PLRS`, `TEAM`, `PROJ`)
2. "What's the AI reviewer's email in Jira?" (e.g., `solomon@company.com`) — or "none" if no AI reviewer exists
3. "Who are your tech leads?" (names that validate tickets — their comments reduce pushback level)

Then guide them to populate author profiles by running the scrape — it auto-discovers authors from ticket data.

```json
{
  "project": "PLRS",
  "ticket_prefix": "PLRS",
  "ai_reviewer": {
    "email": "solomon@repocare.com",
    "display_name": "Solomon",
    "comment_marker": "Solomon — Planning"
  },
  "tech_leads": ["Dennis Vinterfjärd"],
  "author_profiles": {
    "Andreas Höjevik": {
      "role": "tester",
      "pushback_level": "high",
      "known_patterns": ["thin descriptions", "title/description mismatch", "no ACs"],
      "strengths": ["finds real bugs from UAT"],
      "gaps": ["no technical context", "no expected behavior", "no edge cases"]
    },
    "Ludvig Övergaard": {
      "role": "product",
      "pushback_level": "medium",
      "known_patterns": ["detailed ACs", "table formats", "user flows"],
      "strengths": ["good at describing WHAT", "improving structure"],
      "gaps": ["no API contracts", "no migration needs", "no cross-service impacts"]
    },
    "Dennis Vinterfjärd": {
      "role": "tech_lead",
      "pushback_level": "light",
      "known_patterns": ["varies — sometimes detailed, sometimes minimal"],
      "strengths": ["knows intent", "technical context when present"],
      "gaps": ["sometimes no description at all"]
    }
  },
  "ticket_flow": [
    { "from": "Monika Åkvist-Johansson", "to": "Andreas Höjevik", "label": "UAT findings" },
    { "from": "Andreas Höjevik", "to": "Ludvig Övergaard", "label": "product context" },
    { "from": "Ludvig Övergaard", "to": "Dennis Vinterfjärd", "label": "tech review" },
    { "from": "Dennis Vinterfjärd", "to": "AI/Dev Team", "label": "approved for dev" }
  ]
}
```

### Auto-Discovery Mode

If `author_profiles` is empty or missing, the scrape runs in **discovery mode**:
1. Scrape all tickets as normal
2. From the `author_profile` data collected per ticket, aggregate stats per reporter
3. After the scrape, present discovered authors:

```
## Discovered Authors (from N tickets)

| Author | Tickets | Avg Description Length | Has ACs | Has Tech Context | Suggested Pushback |
|--------|---------|----------------------|---------|-----------------|-------------------|
| Person A | 8 | 42 chars | 0% | 0% | HIGH |
| Person B | 5 | 340 chars | 80% | 20% | MEDIUM |
| Person C | 3 | 180 chars | 33% | 100% | LIGHT |

Save these as author profiles? (y/n)
```

If the user confirms, write to `team-profiles.json`.

## Step 1: Load Existing Data

Read `jira-pushback-learnings.json` from the current project's memory directory. Extract already-processed ticket keys. Skip unless `--force`.

If the file doesn't exist, start with `[]`.

## Step 2: Find Tickets with AI Reviewer Comments

Read `ai_reviewer.email` and `project` from `team-profiles.json`.

If an AI reviewer is configured:
```bash
acli jira workitem search --jql 'project = <PROJECT> AND comment ~ "<DISPLAY_NAME>" ORDER BY created DESC' \
  --limit <N> --fields "key,summary,status,issuetype" --json
```

If no AI reviewer (the team wants to analyze ticket quality without an AI reviewer):
```bash
acli jira workitem search --jql 'project = <PROJECT> ORDER BY created DESC' \
  --limit <N> --fields "key,summary,status,issuetype" --json
```

Filter out already-processed ticket keys (unless `--force`).

If `--ticket` was provided, use only that ticket.

## Step 3: Fan Out — 10 Agents in Parallel

Split unprocessed tickets into batches of 10. Launch agents using `subagent_type: "general-purpose"`.

Give each agent **one ticket** to analyze. Pass the ticket key, AI reviewer email (or null), and tech lead names in the prompt. See the **Agent Prompt** below.

Collect all results. If an agent fails or returns malformed JSON, log a warning and skip that ticket.

For large backlogs (>10 unprocessed), run in waves of 10 until all are done.

## Agent Prompt (per ticket)

Use this prompt structure for each agent. Replace `{TICKET_KEY}`, `{REVIEWER_EMAIL}`, and `{TECH_LEADS}` with actual values from `team-profiles.json`.

```
You are extracting structured learnings from Jira ticket comments.

Ticket: {TICKET_KEY}
AI reviewer email: {REVIEWER_EMAIL} (or "none" if no AI reviewer)
Tech leads (names): {TECH_LEADS}

Run these commands in sequence:

1. acli jira workitem view {TICKET_KEY}
2. acli jira workitem comment list --key {TICKET_KEY} --json

From the ticket view, extract: summary, status, type, reporter, assignee, and the full description text.

From the comments, analyze ALL comments. If an AI reviewer email is provided, identify their comments separately.

For EACH AI reviewer comment (skip this section if no AI reviewer), analyze:

1. COMMENT STRUCTURE — What sections does the comment contain?
   - Planning summary (understanding of the ticket)
   - Open questions (unresolved)
   - Resolved questions
   - Suggested acceptance criteria
   - Implementation guidance
   - Risk flags

2. PUSHBACK QUALITY — Rate each aspect:
   - Specificity: Does it ask concrete questions or vague ones?
   - Accuracy: Does its understanding match the ticket description?
   - Completeness: Does it cover edge cases, permissions, error states, i18n, domain model?
   - Actionability: Can the ticket author act on the feedback?

3. TEAM RESPONSE — How did humans respond to the pushback?
   - Were questions answered?
   - Were suggestions accepted or rejected?
   - Did the conversation lead to ticket improvement?
   - Was the AI reviewer's assessment challenged/corrected?

4. GAPS — What did the AI reviewer MISS that it should have caught?
   - Permission/role considerations not mentioned
   - i18n requirements not flagged
   - Error handling gaps not identified
   - Domain model impact not assessed
   - Cross-service implications missed
   - UX flow gaps not spotted

For ALL tickets (with or without AI reviewer), analyze the ticket WRITING QUALITY:

5. AUTHOR PROFILE — Assess the ticket as written by the reporter:
   - How long is the description (character count)?
   - Does it contain acceptance criteria?
   - Does it have screenshots or mockups (check for attachment references)?
   - Does it include technical context (API endpoints, code references, service names)?
   - Does the title match what the description actually asks for?
   - Did any of the tech leads ({TECH_LEADS}) comment on the ticket?

Then return ONLY a JSON object (no markdown, no explanation) in this exact shape:

{
  "ticket": "{TICKET_KEY}",
  "summary": "ticket summary",
  "status": "ticket status",
  "type": "issue type",
  "created": "ISO date or null",
  "reporter": "reporter name",
  "ai_reviewer_comments": [
    {
      "comment_id": "id",
      "comment_type": "planning | followup | clarification",
      "sections_present": ["understanding", "open_questions", "resolved_questions", "acceptance_criteria", "implementation_guidance", "risk_flags"],
      "questions_asked": N,
      "questions_answered_by_team": N,
      "blockers_flagged": N,
      "suggestions_made": N,
      "categories_covered": ["permissions", "i18n", "error_handling", "domain_model", "ux_flow", "api_contract", "testing", "security", "performance", "data_migration", "cross_service"],
      "categories_missed": ["list of areas not covered that should have been"],
      "specificity_score": 1-5,
      "accuracy_score": 1-5,
      "completeness_score": 1-5,
      "actionability_score": 1-5,
      "team_response": "accepted | challenged | ignored | partially_addressed | no_response",
      "notable_catch": "one sentence: best thing caught, or null",
      "notable_miss": "one sentence: biggest thing missed, or null",
      "ended_with_develop_label_prompt": true or false
    }
  ],
  "human_comments_count": N,
  "ai_reviewer_comments_count": N,
  "ticket_improved_after_pushback": true or false,
  "overall_pushback_effectiveness": "high | medium | low | unclear | no_ai_reviewer",
  "author_profile": {
    "reporter": "display name",
    "description_length": N,
    "has_acceptance_criteria": true or false,
    "has_screenshots_or_mockups": true or false,
    "has_technical_context": true or false,
    "title_matches_description": true or false,
    "writing_quality": "thin | adequate | detailed",
    "tech_lead_commented": true or false,
    "tech_lead_name": "name or null"
  }
}

Rules:
- If the AI reviewer comment is a pure status update (e.g., "implementation started", "all questions resolved") with NO planning analysis, questions, or ACs, classify as comment_type: "status_only" and score specificity and actionability as 1. These are noise — they add no value.
- If AI reviewer email is "none", return ai_reviewer_comments: [] and ai_reviewer_comments_count: 0
- Score specificity 1-5: 1=vague generic questions, 5=precise questions with context
- Score accuracy 1-5: 1=misunderstands the ticket, 5=perfect understanding
- Score completeness 1-5: 1=covers only surface, 5=covers all relevant areas
- Score actionability 1-5: 1=unclear what to do next, 5=clear steps for ticket author
- For categories_missed: only include categories genuinely relevant to THIS ticket
- team_response: look at non-AI-reviewer comments after the AI reviewer's comment
- writing_quality: "thin" = <100 chars or no real description, "adequate" = has description with some structure, "detailed" = ACs + context + examples
- Match tech leads by display name (case-insensitive partial match)
- Return ONLY the JSON object, nothing else
```

## Step 4: Merge Results

After each batch completes:

1. Read current `jira-pushback-learnings.json`
2. Append new ticket objects
3. Write back, sorted by `created` descending (newest first)

Also update the checkpoint file:
```json
{
  "last_run": "ISO date",
  "tickets_processed": N,
  "last_ticket_key": "PREFIX-XXXX"
}
```

## Step 5: Analyze Patterns

After all batches complete, analyze across ALL stored learnings (not just this run).

Read `team-profiles.json` to get the AI reviewer display name for output labels.

### Scoring Summary
```
## Jira Pushback Scrape Complete

- Tickets processed this run: N
- Tickets skipped (already stored): N
- Total AI reviewer comments analyzed: N (or "N/A — no AI reviewer configured")

### Average Scores (1-5) [only if AI reviewer configured]
- Specificity:    X.X
- Accuracy:       X.X
- Completeness:   X.X
- Actionability:  X.X
- Overall:        X.X

### Coverage Gaps [only if AI reviewer configured]
1. <category> — missed in N/M tickets (X%)
2. <category> — missed in N/M tickets (X%)
3. ...

### Best Catches [only if AI reviewer configured]
- <ticket>: <notable catch>
- ...

### Biggest Misses [only if AI reviewer configured]
- <ticket>: <notable miss>
- ...

### Team Response Patterns [only if AI reviewer configured]
- Accepted: N (X%)
- Challenged: N (X%)
- Ignored: N (X%)
- Partially addressed: N (X%)
- No response: N (X%)

### Ticket Quality by Author [always shown]
| Author | Tickets | Avg Writing Quality | Has ACs | Title/Desc Match | Tech Lead Input |
|--------|---------|-------------------|---------|-----------------|-----------------|
| <name> | N | thin/adequate/detailed | X% | X% | X% |

### Risk Flag: Thin Tickets Without Tech Lead [always shown]
- N tickets had "thin" descriptions AND no tech lead comment
- These are highest risk for misunderstanding intent
- Authors: <list>

### Author Profile Updates [if auto-discovery found new authors]
- N new authors discovered
- N existing profiles updated with new data
```

## Step 6: Generate Improvement Proposals

Based on the patterns, propose concrete improvements to:

### 1. AI Reviewer Template (if AI reviewer configured)
What sections should the reviewer always include? What's it missing consistently?

### 2. `/ticket-refine` Command
What does the AI reviewer check that `/ticket-refine` doesn't? What does `/ticket-refine` check that the reviewer should?

### 3. Team Knowledge Base
Are there recurring gaps that should be documented?

### 4. Author Profiles
Should any author's pushback level be adjusted based on data?

Format proposals as a routing table compatible with `/retro-proposals`:

```
## Proposed Improvements

| # | Finding | Source | Destination | Proposed Change |
|---|---------|--------|-------------|-----------------|
| 1 | AI reviewer never checks i18n | Coverage gap | skill:ticket-refine | Add i18n check to Step 3 |
| 2 | Team ignores 40% of pushback | Response pattern | memory | Track and escalate ignored pushback |
| 3 | Author X improved to "adequate" | Author trend | team-profiles.json | Lower pushback level from high to medium |
```

Ask the user:
- "Apply improvements via `/retro-proposals`?"
- "Update author profiles in `team-profiles.json`?"
- "Re-run with `--force` to refresh all data?"
- "Analyze a specific ticket deeper with `--ticket PREFIX-XXXX`?"

## Storage Format

`jira-pushback-learnings.json` is an array of ticket objects (see Agent Prompt for shape).

## Tips

- Run periodically to track improvement over time — compare average scores across runs
- The coverage gap analysis is the most actionable output: it tells you exactly what the AI reviewer needs to learn
- Team response patterns reveal whether pushback is too aggressive (high challenge rate) or too weak (high ignore rate)
- **Without an AI reviewer**: This command still provides value — it analyzes ticket writing quality per author and identifies who needs coaching
- Author profiles get better with more data — re-run periodically and the auto-discovery mode will refine pushback levels
- Cross-reference with `/ticket-refine` findings on the same tickets to compare human vs AI review quality
- This command is part of the [Learning System](../docs/learning-system.md) alongside `/scrape-pr-history` and `/pr-insights`
