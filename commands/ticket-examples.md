---
context: fork
---

# Ticket Examples — Code Variation Examples from Codebase

ultrathink — this task requires deep analysis of existing code structures to produce concrete, actionable examples for ticket implementation.

Read a Jira ticket, analyze the relevant codebase, and generate concrete variation examples (data mappings, sentence templates, type definitions, enum combinations, flow descriptions) that clarify what needs to be built. Post the result as a well-formatted comment on the ticket.

Use this when existing patterns/code exist and you need to enumerate all the variations a ticket must handle. Best for tickets involving enums, type mappings, rendering logic, or data transformations where completeness matters.

$ARGUMENTS

## Modes

Parse the arguments to determine what to do:

### Single ticket by ID (e.g. `PROJ-1957`)
Generate examples for the specified ticket.

### No arguments
Ask the user which ticket to work on.

## Workflow

### Step 1 — Read the ticket

```bash
acli jira workitem view --key "<TICKET_ID>" --json
```

Also read existing comments for context (including any `/ticket-refine` pushback):
```bash
acli jira workitem comment list --key "<TICKET_ID>" --json
```

### Step 2 — Understand the domain

From the ticket description and comments, identify:
- What **data structures** are involved (API responses, types, enums, models)
- What **operations/actions** need to be mapped or handled
- What **UI components** will display this data
- What **existing patterns** this should follow

### Step 3 — Explore the codebase

Use the Explore agent to find:
- Relevant TypeScript types, interfaces, and enums
- Existing mapping/rendering code for similar features
- Backend models and API contracts (C# enums, DTOs)
- Translation key patterns
- Seed data examples
- Current behavior vs expected behavior

Be thorough — look at both frontend (`apps/web/`) and backend (`services/`, `shared/`) as needed.

### Step 4 — Generate concrete variation examples

Based on the data structures found, produce **concrete examples** showing:

**Enum/type combinations:**
- Every combination/scenario that needs handling
- Real values from the codebase (enum values, property names, type mappings)
- Mark which combinations already have handling vs which are new

**User-facing output:**
- How each scenario should look to the end user
- Human-readable sentences, formatted values, translated strings
- Show the template/pattern AND a concrete example for each

**Data mappings:**
- Source field → target field for each property
- Type transformations (Date → formatted date, Enum → translated string, etc.)
- Default/fallback values

**Edge cases:**
- Null/undefined handling for each field
- Empty collections
- Invalid or unexpected values
- Proposals for undefined cases (e.g. new enum values with no existing rendering)

Format the examples clearly:
- Group by category/type
- Show the template/pattern AND a concrete example for each
- Call out which data types affect formatting
- Mark proposals/suggestions distinctly from confirmed behavior

### Step 5 — Format for Jira

**IMPORTANT:** ACLI sends comment body as plain text — Jira wiki markup will NOT render. Use plain text formatting:

- Headings: `UPPERCASE` with `====` or `----` underlines
- Lists: `  - item` with indentation
- Examples: `  -> Example: ...` with arrow prefix
- Sections: blank lines between groups
- Emphasis: UPPERCASE for key words, "quotes" for values
- Separators: blank lines (not `----` which shows literally)
- Never use `*`, `_`, `||`, `h2.`, `h3.` — they show as raw characters

### Step 6 — Post to Jira

```bash
# Write to temp file first
# Then post:
acli jira workitem comment create --key "<TICKET_ID>" --body-file "/tmp/examples-<TICKET_ID>.txt"
```

### Step 7 — Summarize

Tell the user:
- What was analyzed
- How many scenarios/combinations were documented
- How many are already handled vs new
- Any gaps where no existing pattern exists
- Link to the ticket

## Guidelines

- **Be exhaustive** — cover every enum value, every type+operation combination, every property. Missing cases cause bugs.
- **Use real data** — pull actual enum values, property names, and type definitions from the codebase. Don't invent examples.
- **Show the user perspective** — every technical mapping should have a human-readable example showing what the user would see.
- **Mark unknowns** — if a scenario has no existing example in the data, mark it as "(PROPOSAL)" and suggest what it should look like.
- **Keep formatting clean** — plain text only for Jira. The comment should be scannable and easy to discuss in refinement.
- **Reference existing code** — include file paths so developers can find the patterns quickly.
- **Don't duplicate /ticket-refine work** — this command focuses on WHAT to build (variations), not WHETHER the ticket is ready (quality). If the ticket needs refinement first, suggest running `/ticket-refine` instead.
