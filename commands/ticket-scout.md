---
context: fork
---

# Ticket Scout — Sprint Triage & Story Points

ultrathink — this task requires reasoning across multiple tickets to assess relative complexity and assign fair story points.

Batch-scan upcoming Jira tickets, assign story points (1-4), and flag obvious blockers. This is a quick triage — not deep analysis. Use `/ticket-refine` for deep single-ticket refinement.

$ARGUMENTS

## Already-Scouted Tracking

Previously scouted tickets (skip these unless `--force` or single ticket by ID):

!`cat ~/.claude/projects/-Users-username/memory/scouted-tickets.json 2>/dev/null || echo "[]"`

This is a JSON array of objects tracking previously scouted tickets:

```json
[
  { "key": "PROJ-1234", "scoutedAt": "2026-02-21", "points": 2, "team": "Kenji + Ingrid" }
]
```

**Skip tickets that are already in this file** unless the user passes `--force` or scouts a single ticket by ID. After scouting new tickets, append them to this file.

When presenting results, show skipped tickets as: "PROJ-1234 — already scouted (2026-02-21, 2 pts)"

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

### `<TICKET-ID>` — Scout a single ticket
View full details of one ticket. Don't skip even if already scouted.

## Story Points Scale

Assign points 1-4 based on effort and risk. These map roughly to t-shirt sizes:

| Points | Size | Typical scope | Examples |
|--------|------|---------------|----------|
| **1** | S | Single file/component, one service, trivial change | Copy change, styling fix, config update |
| **2** | M | 2-5 files, one service or light full-stack, clear path | New form field end-to-end, simple API endpoint, component refactor |
| **3** | L | 5-10 files, full-stack, some unknowns or coordination | New feature with API + UI + translations, multi-step form, new list/detail view |
| **4** | XL | 10+ files, multiple services, domain model changes, high risk | New entity/domain concept, cross-service feature, migration-heavy work, new page with complex state |

### Calibration rules
- If it needs a **new database table or EF migration** → minimum 3 points
- If it touches **3+ services** → minimum 3 points
- If **acceptance criteria are vague** → bump up 1 point (uncertainty tax)
- If it's **purely frontend styling** with clear specs → likely 1 point
- If it needs **new API endpoints** → minimum 2 points
- If the work is **mechanical/repetitive** (same pattern applied N times, e.g., writing similar tests, config setup, adding fields to existing forms) → keep low even if many files — count distinct problems, not files touched
- **Infrastructure/config tickets** (adding tooling, npm scripts, directory structure) are typically 1 point — the real work is what uses the infrastructure

## For Each Ticket

1. **Fetch the ticket details** including description and comments:
   ```bash
   acli jira workitem view <KEY> --json
   ```

2. **Quick analysis** (reasoning only, NO codebase exploration — this must be cheap):

   | Dimension | Assessment |
   |-----------|------------|
   | **Story points** | 1 / 2 / 3 / 4 |
   | **Scope** | backend-only / frontend-only / full-stack |
   | **Team** | Which Dream Team agents needed |
   | **Model tier** | Recommended model per agent |
   | **Verdict** | See below |

3. **Assign a verdict** for each ticket:

   | Verdict | Meaning | Next step |
   |---------|---------|-----------|
   | READY | Clear enough to start work | Go to `/create-stories` |
   | REFINE | Has gaps but worth doing — needs `/ticket-refine` first | Run `/ticket-refine <ID>` |
   | PUSH BACK | Not ready — missing critical info, contradictory, or questionable value | Post questions to Jira, discuss with PO |
   | SKIP | Too vague, duplicate, or not worth the effort | Flag to PO with reason |

   **Verdict criteria:**
   - READY: Has clear ACs, description matches title, scope is obvious, no domain model ambiguity
   - REFINE: Has ACs but they're incomplete, or implies domain changes that need investigation, or 3-4 points with unknowns
   - PUSH BACK: No ACs, contradictory info, missing context that blocks even rough sizing, unclear business value
   - SKIP: Description is a single sentence with no context, duplicate of another ticket, effort clearly outweighs value

4. **Flag obvious risks** — keep it brief:
   - "No acceptance criteria"
   - "Implies domain model change (new entity mentioned)"
   - "Dependencies on other tickets"
   - "Conflicting description and title"
   - "Questionable value — effort vs impact unclear"

## Output

Write the analysis to `~/.claude/projects/-Users-username/memory/ticket-scout.md`:

```markdown
# Ticket Scout — [date]

## Summary
- Tickets analyzed: N
- Total points: X (estimated)
- Distribution: 1pt(x) 2pt(x) 3pt(x) 4pt(x)
- Verdicts: READY(x) REFINE(x) PUSH BACK(x) SKIP(x)

## Tickets

### PROJ-1234 — [summary]
| Points | Scope | Team | Verdict |
|--------|-------|------|---------|
| 2 | full-stack | Kenji + Ingrid | READY |

### PROJ-1235 — [summary]
| Points | Scope | Team | Verdict |
|--------|-------|------|---------|
| 4 | full-stack | Full team | REFINE |
Reason: Implies new database entity but no schema described. Run /ticket-refine first.

### PROJ-1236 — [summary]
| Points | Scope | Team | Verdict |
|--------|-------|------|---------|
| ? | unclear | ? | PUSH BACK |
Reason: Single-sentence description, no ACs, no mockup. Not ready for estimation.

---
[repeat for each ticket]
```

Present the report to the user as a clean table and save it.

## Token Budget

- **Batch mode**: Read full details for max 10 tickets. If more exist, show a summary list and let the user pick.
- **Single ticket mode**: No limit — read everything including comments.
- Summarize descriptions rather than quoting in full.

## Optional: Post Points to Jira

After analysis, ask the user:
- "Should I set story points on the tickets?"
- If yes, use the REST API script (ACLI doesn't support custom fields):
  ```bash
  bash ~/.claude/scripts/jira-set-field.sh <KEY> customfield_10437 <N>
  ```
