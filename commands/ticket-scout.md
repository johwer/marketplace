# Ticket Scout — Pre-Analyze Upcoming Work

ultrathink — this task requires deep reasoning to catch ambiguity, scope risks, and missing requirements.

Scan upcoming Jira tickets, pre-analyze them, and write observations so the Dream Team starts each ticket with better context.

$ARGUMENTS

## Already-Scouted Tracking

Before analyzing any ticket, read `~/.claude/projects/-Users-johanwergelius/memory/scouted-tickets.json`. This is a JSON array of objects tracking previously scouted tickets:

```json
[
  { "key": "PLRS-1234", "scoutedAt": "2026-02-21", "complexity": "M", "team": "Kenji + Ingrid" }
]
```

**Skip tickets that are already in this file** unless the user passes `--force` or scouts a single ticket by ID. After scouting new tickets, append them to this file.

When presenting results, show skipped tickets as: `⏭️ PLRS-1234 — already scouted (2026-02-21)`

## Modes

Parse the arguments to determine what to do:

### No arguments — Scout my assigned tickets
Fetch open tickets assigned to the current user:

```bash
acli jira workitem search --jql "project = PLRS AND assignee = currentUser() AND status not in (Done) ORDER BY priority DESC" --fields "key,summary,status,story_points" --json
```

### `sprint` — Scout next sprint (unassigned included)
```bash
acli jira workitem search --jql "project = PLRS AND sprint in openSprints() AND status not in (Done) ORDER BY priority DESC" --fields "key,summary,status,assignee,story_points" --json
```

### `uat` — Scout UAT/review tickets
```bash
acli jira workitem search --jql "project = PLRS AND status in ('UAT', 'Review', 'QA') ORDER BY updated DESC" --fields "key,summary,status,assignee" --json
```

### `done [N]` — Learn from last N completed tickets (default 5)
```bash
acli jira workitem search --jql "project = PLRS AND status = Done AND assignee = currentUser() ORDER BY updated DESC" --fields "key,summary,status" --limit N --json
```

### `<TICKET-ID>` — Deep scout a single ticket
View full details of one ticket including description and comments.

## For Each Ticket

1. **Fetch the ticket details** including description and comments:
   ```bash
   acli jira workitem view <KEY> --json
   ```

2. **Analyze and rate** (do this with reasoning, don't call APIs):

   | Dimension | Rating | Notes |
   |-----------|--------|-------|
   | **Complexity** | S / M / L / XL | Based on scope: how many services, files, features |
   | **Requirements quality** | 🟢 Clear / 🟡 Partial / 🔴 Vague | Are acceptance criteria specific? Missing edge cases? |
   | **Team composition** | e.g., "Kenji + Ingrid" | Which Dream Team agents would be needed |
   | **Model tier** | e.g., "Kenji: sonnet, Ingrid: haiku" | Recommended model per agent |
   | **Needs testing** | Yes / No | Would Suki be needed? |
   | **Infra concerns** | Yes / No | Would Diego be needed? (migrations, Docker, new services) |
   | **Collaboration risk** | Low / Medium / High | How much cross-agent coordination is needed |
   | **Missing info** | List of questions | What should be clarified before starting |

3. **Flag requirement gaps** — Be specific:
   - "No acceptance criteria listed"
   - "Says 'update the form' but doesn't specify which fields"
   - "Missing error handling requirements"
   - "No mention of i18n for new UI text"
   - "API contract not defined — backend and frontend will need to agree"

## Output

### For scouting mode (my tickets / sprint / uat)

Write the analysis to `~/.claude/projects/-Users-johanwergelius/memory/ticket-scout.md`:

```markdown
# Ticket Scout Report — [date]

## Summary
- Tickets analyzed: N
- Complexity: S(x) M(x) L(x) XL(x)
- Requirements quality: 🟢(x) 🟡(x) 🔴(x)
- Total estimated agents needed: N unique agents across all tickets

## Tickets

### PLRS-1234 — [summary]
| Dimension | Rating |
|-----------|--------|
| Complexity | M |
| Requirements | 🟡 Partial |
| Team | Kenji (sonnet) + Ingrid (sonnet) |
| Testing | Yes — API behavior change |
| Infra | No |
| Collaboration | Medium — API contract needed |

**Missing info:**
- No error handling for invalid input specified
- Which user roles can access this feature?

**Pre-observation for Dream Team:**
> Start with API contract definition. The ticket mentions "similar to the settings page" — check `apps/web/src/pages/Settings/` for patterns. Backend changes are in HCM service only.

---
[repeat for each ticket]
```

Present the report to the user and save it.

### For learning mode (`done`)

Read completed tickets and extract patterns. Write to `~/.claude/projects/-Users-johanwergelius/memory/ticket-patterns.md`:

```markdown
# Ticket Patterns — Learned from completed work

## Last updated: [date]
## Tickets analyzed: N

### Complexity Calibration
- Small tickets (S): [common characteristics — e.g., "single service, 1-3 files, styling or copy changes"]
- Medium tickets (M): [common characteristics]
- Large tickets (L): [common characteristics]

### Common Requirement Gaps
- [Pattern that keeps recurring — e.g., "i18n keys never mentioned but always needed for UI tickets"]

### Team Composition Patterns
- Backend-only tickets: [frequency, typical complexity]
- Frontend-only tickets: [frequency, typical complexity]
- Full-stack tickets: [frequency, what made them complex]

### What Caused Extra Review Rounds
- [Pattern from tickets that had multiple review cycles]
```

## Token Budget

This command reads ticket descriptions and comments which can be verbose. To manage token cost:

- **Sprint/my tickets mode**: Read full details for max 10 tickets. If more exist, show a summary list and let the user pick which ones to deep-scout.
- **Done mode**: Read max 5 tickets by default. Use `done 10` to increase.
- **Single ticket mode**: No limit — read everything including all comments.
- **Skip attachments**: Don't try to download Jira attachments (they require browser auth anyway).
- For each ticket, summarize the description in your analysis rather than quoting it in full.

## Optional: Write Jira Comments

After analysis, ask the user:
- "Should I add pre-observations as Jira comments on the tickets?"
- If yes, add a comment to each analyzed ticket:
  ```bash
  acli jira workitem comment create --key "<KEY>" --body "🔍 **Dream Team Pre-Scout**

  **Complexity:** M | **Team:** Kenji + Ingrid | **Model:** sonnet + sonnet
  **Requirements:** 🟡 Partial — missing error handling spec and i18n requirements
  **Notes:** Check Settings page for UI patterns. API contract needed before parallel work.

  _Auto-generated by Dream Team Ticket Scout_"
  ```
