---
context: fork
---

# Refine Ticket — Generate Proposal Examples from Codebase

ultrathink — this task requires deep analysis of existing code structures to produce concrete, actionable examples for ticket refinement.

Read a Jira ticket, analyze the relevant codebase, and generate concrete proposal examples (data mappings, sentence templates, type definitions, flow descriptions, etc.) that clarify acceptance criteria. Post the result as a well-formatted comment on the ticket.

$ARGUMENTS

## Modes

Parse the arguments to determine what to do:

### Single ticket by ID (e.g. `PROJ-1957`)
Refine the specified ticket.

### No arguments
Ask the user which ticket to refine.

## Workflow

### Step 1 — Read the ticket

```bash
acli jira workitem view --key "<TICKET_ID>" --json
```

Also read existing comments for context:
```bash
acli jira workitem comment list --key "<TICKET_ID>" --json
```

### Step 2 — Understand the domain

From the ticket description and comments, identify:
- What **data structures** are involved (API responses, types, enums, models)
- What **operations/actions** need to be mapped or handled
- What **UI components** will display this data
- What is **unclear or missing** from the ticket

### Step 3 — Explore the codebase

Use the Explore agent to find:
- Relevant TypeScript types, interfaces, and enums
- Existing mapping/rendering code
- Backend models and API contracts (C# enums, DTOs)
- Translation key patterns
- Current behavior vs expected behavior

Be thorough — look at both frontend (`apps/web/`) and backend (`services/`, `shared/`) as needed.

### Step 4 — Generate concrete proposals

Based on the data structures found, produce **concrete examples** showing:
- Every combination/scenario that needs handling
- Real values from the codebase (enum values, property names, type mappings)
- How each scenario should look to the end user (human-readable sentences, formatted values)
- Proposals for undefined cases (e.g. delete operations with no existing examples)

Format the examples clearly:
- Group by category/type
- Show the template/pattern AND a concrete example for each
- Call out which data types affect formatting (Date → formatted date, String → translated, Number → raw)
- Mark proposals/suggestions distinctly from confirmed behavior

### Step 5 — Format for Jira

**IMPORTANT:** The ACLI sends comment body as plain text — Jira wiki markup (`*bold*`, `_italic_`, `h2.`, `||table||`) will NOT render. Use plain text formatting:

- Headings: `UPPERCASE` with `====` or `----` underlines
- Lists: `  - item` with indentation
- Examples: `  → Example: ...` with arrow prefix
- Sections: blank lines between groups
- Emphasis: UPPERCASE for key words, "quotes" for values
- Separators: blank lines (not `----` which shows literally)
- Never use `*`, `_`, `||`, `h2.`, `h3.` — they show as raw characters

### Step 6 — Post to Jira

```bash
# Write to temp file first
# Then post:
acli jira workitem comment create --key "<TICKET_ID>" --body-file "/tmp/refine-<TICKET_ID>.txt"
```

### Step 7 — Summarize

Tell the user:
- What was analyzed
- How many scenarios/combinations were documented
- Any open questions or areas that need PO/team input
- Link to the ticket

## Guidelines

- **Be exhaustive** — cover every enum value, every type+operation combination, every property. Missing cases cause bugs.
- **Use real data** — pull actual enum values, property names, and type definitions from the codebase. Don't invent examples.
- **Show the user perspective** — every technical mapping should have a human-readable example sentence showing what the user would see.
- **Mark unknowns** — if a scenario has no existing example in the data, mark it as "(proposal)" and suggest what it should look like.
- **Keep formatting clean** — plain text only for Jira. The comment should be scannable and easy to discuss in refinement.
