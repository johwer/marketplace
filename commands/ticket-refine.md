---
context: fork
---

# Ticket Refine — Quality Gate & Pushback

ultrathink — this task requires deep critical analysis of ticket quality, domain implications, UX flows, and consistency to produce actionable pushback.

Deep-analyze a single Jira ticket before work starts. Find what's missing, contradictory, or risky. Push back with concrete questions. This is the quality gate between sprint planning and implementation.

Depth scales with complexity — don't burn tokens deep-analyzing a 1-point styling fix.

$ARGUMENTS

## Modes

Parse the arguments to determine what to do:

### Single ticket by ID (e.g. `PROJ-1957`)
Refine the specified ticket.

### Single ticket with points hint (e.g. `PROJ-1957 2`)
Refine the ticket at the specified depth (points = depth). Useful when coming from `/ticket-scout` which already estimated points.

### No arguments
Ask the user which ticket to refine.

## Depth Scaling

The analysis depth scales with story points (estimated or provided). This saves tokens on simple tickets and goes deep where it matters.

| Points | Depth | What to check |
|--------|-------|---------------|
| **1** | Light | Step 1 (read) + Step 2 (consistency) only. Quick sanity check. Skip codebase scan, UX flow, domain model. |
| **2** | Medium | Steps 1-3 (read, consistency, completeness audit). Light domain model check. Skip deep UX flow analysis. |
| **3** | Deep | Steps 1-5 (everything except codebase scan can be lighter). Full domain model and UX analysis. |
| **4** | Full | All steps at maximum depth. Full codebase scan, all roles, all flows. |

If no points are provided, estimate from the ticket description and apply the matching depth.

## Knowledge Base Reference

Before analyzing, read the team knowledge base:
```
~/.claude/docs/team-knowledge-base.md
```

Cross-reference the ticket against **known gaps** in the knowledge base. If the ticket touches a documented gap area (permissions, cross-service flows, domain knowledge, etc.), flag it specifically:
- "This ticket involves permission permutations — this is a known gap area (see knowledge base). Requires explicit permission matrix before implementation."
- "This ticket creates/updates service-as — cross-service event flow is not documented. Which services are affected?"

After refinement, if new gaps or patterns are discovered, update the knowledge base.

## Ticket Refinement History

Previously refined tickets are tracked in:
```
~/.claude/projects/-Users-username/memory/ticket-refinements.json
```

!`cat ~/.claude/projects/-Users-username/memory/ticket-refinements.json 2>/dev/null || echo "[]"`

Each entry records the refinement outcome so future sessions can reference past findings:

```json
[
  {
    "key": "PROJ-1234",
    "refinedAt": "2026-03-06",
    "points": 3,
    "depth": "deep",
    "verdict": "needs-signoff",
    "signoff": {
      "required": ["PO", "UX"],
      "received": ["PO"],
      "missing": ["UX"]
    },
    "blockers": 2,
    "questions": 3,
    "domainModelChange": true,
    "knowledgeGaps": ["permissions", "cross-service-flow"],
    "notes": "New service-a type requires permission matrix sign-off and UX flow review"
  }
]
```

If the ticket was already refined, show the previous findings and ask: "Re-refine or continue from previous?"

## Workflow

### Step 1 — Read the ticket thoroughly (ALL depths)

```bash
acli jira workitem view --key "<TICKET_ID>" --json
```

Also read existing comments for context:
```bash
acli jira workitem comment list --key "<TICKET_ID>" --json
```

Download and review any attachments (screenshots, mockups, PDFs):
```bash
bash ~/.claude/scripts/jira-download-attachments.sh <TICKET_ID>
```

### Step 1b — Check sign-off (ALL depths)

Determine who created/owns the ticket and whether the right people have signed off:

**Sign-off roles to check:**
- **PO** — Has a Product Owner approved the business requirement?
- **UX** — If UI changes: has UX/design reviewed and approved mockups?
- **Architect** — If domain model changes: has an architect reviewed the approach?
- **QA** — If complex flows: has QA been consulted on test strategy?

**How to detect sign-off:**
- Check ticket reporter and assignee fields
- Check comments for explicit approvals or review notes from relevant people
- Check if linked design documents or Figma files exist
- Check if the ticket has been through a refinement meeting (look for status transitions or labels)

**Flag missing sign-offs as blockers:**
- "This ticket changes the permission model but has no architect sign-off"
- "UI mockups don't match description — needs UX review before implementation"
- "No PO confirmation on edge case behavior for [specific scenario]"

Read all downloaded files with the Read tool to understand visual context.

### Step 2 — Consistency check (ALL depths)

Cross-reference ALL parts of the ticket against each other. Flag any conflicts:

**Title vs Description:**
- Does the title accurately reflect what the description asks for?
- Is the scope in the title narrower/broader than the description?

**Description vs Acceptance Criteria:**
- Do the ACs cover everything described?
- Are there described features without ACs?
- Are there ACs that go beyond the description?

**Description vs Attachments:**
- Do screenshots/mockups match what's described?
- Are there UI elements in mockups not mentioned in text?
- Are there described elements missing from mockups?

**Internal contradictions:**
- Does the ticket say one thing in one place and another elsewhere?
- Are there implicit assumptions that conflict?

### Step 3 — Completeness audit (depth 2+)

Check for missing information the AI team needs:

**Structure quality:**
- [ ] Has a clear summary/title
- [ ] Has a description with context (why, not just what)
- [ ] Has acceptance criteria (specific, testable)
- [ ] Has mockups/screenshots if UI-related
- [ ] Has API contract if backend-related
- [ ] Specifies affected user roles
- [ ] Mentions edge cases and error states

**Common gaps to flag:**
- No mention of i18n/translations for new UI text
- No error handling requirements (what happens when X fails?)
- No loading/empty states specified
- No mention of permissions/role access
- No mobile/responsive considerations
- No mention of existing data migration if changing data model
- Missing "definition of done" beyond happy path

### Step 4 — Domain model impact (depth 2+ light, depth 3+ full)

Analyze if the ticket implies changes to the data model:

- **New entities**: Does this need a new database table?
- **Changed relationships**: New foreign keys, changed cardinality?
- **New properties**: New columns on existing tables?
- **Enum changes**: New values, renamed values?
- **EF migrations**: Will this require a migration? Breaking or additive?
- **API contract changes**: New endpoints? Changed response shapes? Breaking changes?
- **Seed data**: Does existing seed data need updating?

If ANY domain model changes are detected, flag them prominently — these are the highest-risk items and need explicit confirmation.

### Step 5 — UX flow analysis (depth 3+)

Map the user experience across different roles and scenarios:

**Role coverage:**
- Which user roles are affected? (admin, manager, employee, HR, etc.)
- Does each role have the same experience or different?
- Are there permission boundaries the ticket doesn't mention?

**Flow completeness:**
- What's the full user journey? (entry point → action → confirmation → result)
- Are there branching paths not covered?
- What happens on the "unhappy path"? (errors, cancellations, timeouts)
- Is there a back/undo mechanism?

**UX red flags:**
- Annoying patterns: unnecessary confirmations, lost form state, forced page reloads
- Broken flows: dead ends, missing navigation, orphaned states
- Inconsistency: different patterns than existing similar features
- Accessibility: missing for keyboard/screen reader users

### Step 6 — Codebase quick scan (depth 4 only)

Use the Explore agent to check:
- Does similar functionality already exist? (avoid duplication)
- What existing patterns should this follow?
- Are there shared components that should be reused?
- Are there "hot files" this would touch that other tickets might also change?

This is NOT the deep code analysis that `/ticket-examples` does — just enough to understand feasibility and spot conflicts.

### Step 7 — Generate pushback (ALL depths — scope matches depth)

Categorize all findings into:

**BLOCKER** — Cannot start work without this resolved:
- Missing information that blocks implementation decisions
- Contradictions that make the requirement ambiguous
- Domain model changes that need architect/PO sign-off

**QUESTION** — Need clarity but could start with assumptions:
- Unclear edge cases
- Unspecified role behavior
- Performance expectations

**SUGGESTION** — Improvements the team should consider:
- UX flow improvements
- Technical approach recommendations
- Existing patterns to reuse

**TICKET WRITING TIP** — How this ticket could have been written better:
- What was unclear and how to phrase it clearly
- What sections were missing
- What format would have helped (table, mockup, flow diagram)

### Step 8 — Format and post to Jira (ALL depths)

**IMPORTANT:** ACLI sends comment body as plain text — Jira wiki markup will NOT render. Use plain text formatting:

- Headings: `UPPERCASE` with `====` or `----` underlines
- Lists: `  - item` with indentation
- Emphasis: UPPERCASE for key words, "quotes" for values
- Separators: blank lines between groups
- Never use `*`, `_`, `||`, `h2.`, `h3.` — they show as raw characters

Structure the comment:

```
TICKET REFINEMENT — <TICKET_ID>
================================

SIGN-OFF STATUS
---------------
  PO:        [OK / MISSING — no PO approval found]
  UX:        [OK / MISSING / N/A — no UI changes]
  Architect: [OK / MISSING / N/A — no domain model changes]
  QA:        [OK / MISSING / N/A — low complexity]

BLOCKERS (must resolve before starting)
---------------------------------------
  1. <concrete blocker with specific question>
  2. ...

QUESTIONS (need clarity)
------------------------
  1. <specific question about edge case or role>
  2. ...

SUGGESTIONS
-----------
  - <recommendation>
  - ...

DOMAIN MODEL IMPACT
-------------------
  <summary of any data model changes detected, or "None detected">

UX FLOW NOTES
-------------
  - Roles affected: <list>
  - <flow observation>
  - ...
```

Write to temp file and post:
```bash
acli jira workitem comment create --key "<TICKET_ID>" --body-file "/tmp/refine-<TICKET_ID>.txt"
```

### Step 9 — Update writing tips library (ALL depths)

After posting, check if any ticket writing tips are new patterns worth saving. Update the coaching file:

```
~/.claude/projects/-Users-username/memory/ticket-writing-tips.md
```

Only add genuinely new patterns — check existing tips first. Format:

```markdown
# Ticket Writing Tips — Learned Patterns

## Structure
- <tip about how to structure tickets>

## Common Gaps
- <recurring missing information>

## Good Examples
- <what a well-written ticket looks like for common types>
```

### Step 10 — Save refinement history (ALL depths)

Append the refinement result to the tracking file:
```
~/.claude/projects/-Users-username/memory/ticket-refinements.json
```

Read the current file, append a new entry with:
- key, refinedAt, points, depth, verdict
- signoff: required/received/missing
- blockers count, questions count
- domainModelChange: true/false
- knowledgeGaps: which knowledge base areas were flagged
- notes: one-line summary

Also update the knowledge base (`~/.claude/docs/team-knowledge-base.md`) if new gaps or patterns were discovered.

### Step 11 — Summarize to user (ALL depths)

Tell the user:
- Sign-off status (who approved, who's missing)
- Number of blockers / questions / suggestions found
- Whether domain model changes are involved
- Which roles are affected
- Recommendation: "Ready to start" / "Needs PO input first" / "Needs design clarification" / "Needs sign-off from [role]"
- Link to the ticket

## Guidelines

- **Be specific** — "Missing error handling" is useless. "What should happen when the API returns 409 because the employee was already archived?" is useful.
- **Push back constructively** — The goal is better outcomes, not criticism. Frame as questions when possible.
- **Prioritize blockers** — A ticket with 0 blockers and 5 suggestions is fine to start. A ticket with 1 blocker needs resolution first.
- **Use the writing tips library** — Reference accumulated patterns to make coaching relevant, not generic.
- **Think from the developer's perspective** — What would make YOU stuck halfway through implementation?
- **Don't over-refine trivial tickets** — A 1-point styling fix doesn't need UX flow analysis. Scale the depth to the ticket's complexity.
