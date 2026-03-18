---
name: triage-issue
description: Triage a bug by exploring the codebase to find root cause, then create a Jira ticket with a TDD-based fix plan. Use when user reports a bug, mentions "triage", or wants to investigate and plan a fix.
autoTrigger:
  - when user reports a bug and wants to investigate it
  - when user says "triage" or "investigate this bug"
globs:
  - "**/*"
---

# Triage Issue

Investigate a reported problem, find its root cause, and create a Jira ticket with a TDD fix plan. This is a mostly hands-off workflow — minimize questions to the user.

## What the User Provides

$ARGUMENTS

If no description is provided, ask ONE question: "What's the problem you're seeing?"

Do NOT ask follow-up questions. Start investigating immediately.

## Process

### Step 1 — Explore and diagnose

Use the Agent tool with subagent_type=Explore to deeply investigate the codebase. Your goal is to find:

- **Where** the bug manifests (frontend component, API endpoint, service method, DB query)
- **What** code path is involved (trace the full flow)
- **Why** it fails (root cause, not just the symptom)
- **What** related code exists (similar patterns, tests, adjacent modules)

Look at:
- Related source files and their dependencies
- Existing tests (what's covered, what's missing)
- Recent changes to affected files: `git log --oneline -10 -- <file>`
- Error handling in the code path
- Similar patterns elsewhere that work correctly

**Stack-aware investigation:**
- Frontend bugs: start in `apps/web/src/` — components, hooks, RTK Query slices
- Backend bugs: start in `services/<Service>/` — controllers, services, repositories
- Cross-service bugs: check event flows, API contracts, and serialization

### Step 2 — Identify the fix approach

Based on investigation, determine:

- The minimal change needed to fix the root cause
- Which layer is affected (frontend / backend / both)
- What behaviors need to be verified via tests
- Whether this is a regression, missing feature, or design flaw

### Step 3 — Design TDD fix plan

Create a concrete, ordered list of RED-GREEN cycles. Each cycle is one vertical slice:

- **RED**: Describe a specific test that captures the broken/missing behavior
- **GREEN**: Describe the minimal code change to make that test pass

Rules:
- Tests verify behavior through public interfaces, not implementation details
- One test at a time — NOT all tests first, then all code
- Each test should survive internal refactors
- Include a final refactor step if needed
- Tests assert on observable outcomes (API responses, UI state, rendered output) — not internal state

**Stack-specific test patterns:**
- Frontend: Vitest + React Testing Library — assert on rendered output or hook return values
- Backend: xUnit + NSubstitute + FluentAssertions — assert on service return values or repository calls

### Step 4 — Create the Jira ticket

Create a new bug ticket in Jira using ACLI:

```bash
# Create the ticket
acli jira workitem create \
  --project PLRS \
  --type Bug \
  --title "<concise bug title>" \
  --body-file /tmp/triage-<slug>.txt
```

Write the body to `/tmp/triage-<slug>.txt` first using this template:

```
TRIAGE: <TICKET_TITLE>
======================

PROBLEM
-------
What happens (actual behavior):
  <describe>

What should happen (expected behavior):
  <describe>

How to reproduce:
  <steps if known>

ROOT CAUSE ANALYSIS
-------------------
  <Describe the code path and why it fails. Use module/layer names,
   not file paths — those change. Describe behaviors and contracts.>

TDD FIX PLAN
------------
  1. RED:   Write a test that <expected behavior>
     GREEN: <minimal change to make it pass>

  2. RED:   Write a test that <next behavior>
     GREEN: <minimal change to make it pass>

  REFACTOR: <Any cleanup after all tests pass>

ACCEPTANCE CRITERIA
-------------------
  - [ ] <criterion 1>
  - [ ] <criterion 2>
  - [ ] All new tests pass
  - [ ] Existing tests still pass
```

After creating the ticket, print the ticket key (e.g. PROJ-1234) and a one-line summary of the root cause.

### Step 5 — Offer next steps

Ask the user:
- "Want me to start a worktree and implement the fix? (`/workspace-launch <TICKET_KEY>`)"
- "Or should I just leave the ticket for the team?"
