---
name: request-refactor-plan
description: Create a detailed refactor plan with tiny commits via user interview, then file it as a Jira ticket. Use when planning a refactor, creating a refactoring RFC, or breaking a refactor into safe incremental steps.
autoTrigger:
  - when user wants to plan a refactor
  - when user mentions "refactor plan", "RFC", or "safe incremental steps"
globs:
  - "**/*"
---

# Request Refactor Plan

Create a structured refactor plan through deep interview and codebase exploration, then file it as a Jira ticket for the team.

## What the User Provides

$ARGUMENTS

## Workflow

### Step 1 — Understand the problem

Ask the user for a detailed description of:
- What problem they're trying to solve (not just "clean this up" — why does it matter?)
- Any ideas they already have for the solution
- What triggered this refactor now (new feature blocked by it? bug pattern? team pain?)

### Step 2 — Explore and verify

Use the Explore agent to understand the current state:
- What does the code actually look like today?
- Does the problem the user described match what's in the codebase?
- What's the test coverage of this area?
- What other code depends on the area being refactored?
- Any recent git history that explains why it got this way?

Report back: "Here's what I found..." before proceeding.

### Step 3 — Consider alternatives

Present 2-3 alternative approaches before interviewing on implementation. Ask:
- "Have you considered [alternative]?"
- "What makes your proposed approach better than [alternative]?"

This surfaces assumptions and ensures the planned solution is the right one.

### Step 4 — Interview on implementation

Go deep on the specifics. Be thorough — vague plans produce bad refactors:

- **Scope**: What's changing? What's explicitly NOT changing?
- **Interfaces**: Which public APIs / component props / service methods change shape?
- **Data model**: Any schema or EF migration changes?
- **Layering**: Does this change which layer owns which logic?
- **Consumers**: Who calls the thing being refactored? Will they need updates?
- **Feature flags**: Does this need a flag or can it land clean?
- **Rollback**: If something goes wrong mid-refactor, what's the recovery plan?

### Step 5 — Assess test coverage

Check the current test coverage of the area:
- Frontend: are there Vitest tests for the hooks/components being changed?
- Backend: are there xUnit tests for the services/repositories being changed?

If coverage is insufficient, ask: "There are no tests covering [area]. How do you want to handle this — write characterization tests first, or proceed carefully with manual verification?"

Don't proceed until there's a clear answer. Refactors without tests are the highest-risk code changes in the codebase.

### Step 6 — Plan tiny commits

Break the refactor into the smallest possible commits. Follow Martin Fowler's rule: **every commit leaves the codebase in a working state**. Tests pass after every single step.

Format each commit as:
```
[n]. <verb> <what changes>
     Why: <one sentence on why this step is isolated>
     Risk: <low / medium — and what could go wrong>
```

Example pattern for a service extraction:
```
1. Add INewService interface (no implementation yet)
   Why: Establishes the contract before touching anything
   Risk: Low — additive only

2. Implement NewService behind the interface (not wired up)
   Why: Build and test in isolation before integrating
   Risk: Low — not called yet

3. Wire NewService into DI container alongside OldService
   Why: Both exist simultaneously — no callers broken
   Risk: Low — parallel run

4. Migrate callers one at a time to NewService
   Why: Each migration is independently rollbackable
   Risk: Medium — test each caller after migration

5. Delete OldService
   Why: Cleanup only after all callers verified
   Risk: Low — all callers already migrated
```

### Step 7 — Create the Jira ticket

Write the plan to `/tmp/refactor-plan-<slug>.txt` then create the ticket:

```bash
acli jira workitem create \
  --project PLRS \
  --type Task \
  --title "Refactor: <concise title>" \
  --body-file /tmp/refactor-plan-<slug>.txt
```

Use this template for the body (plain text — no Jira wiki markup):

```
PROBLEM STATEMENT
-----------------
<The problem from the developer's perspective. Why does this need fixing?>

SOLUTION
--------
<The chosen approach and why it was selected over alternatives.>

COMMIT PLAN
-----------
<The full tiny-commit breakdown from Step 6. Be detailed.>

DECISIONS
---------
  - Modules affected: <list>
  - Interface changes: <describe — no file paths>
  - Schema/migration changes: <describe or "none">
  - API contract changes: <describe or "none">
  - Key architectural decisions made: <list>

TESTING APPROACH
----------------
  - What makes a good test here: only test external behavior, not internals
  - Modules to test: <list>
  - Existing test patterns to follow: <reference similar test files by description, not path>
  - Coverage gaps to address first: <if any>

OUT OF SCOPE
------------
<Explicitly list what is NOT changing in this refactor.>

NOTES
-----
<Anything else the implementer should know.>
```

After creating the ticket, print the ticket key and a one-line summary of the plan.

### Step 8 — Offer next steps

- "Want to start implementation now? (`/workspace-launch <TICKET_KEY>`)"
- "Or leave it for sprint planning?"
