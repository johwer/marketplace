---
name: ticket-coverage
description: Check whether a PR does what its Jira ticket asks. Enumerates every requirement, acceptance criterion, flow and decision from the ticket, its subtasks, parent and comments — a complete list, not a sample — and maps each one to evidence in the PR (file:line or test), MISSING, or OUT OF SCOPE with a reason. Missing requirements become review findings. Use when reviewing a PR that references a ticket, before going ready on your own branch, or when asked "covers the ticket?", "täcker PR:en ärendet?", "är allt i ärendet gjort?".
user_invocable: true
---

## The rule: enumerate, do not sample

A review that reads the diff finds what is wrong with the code. It never finds what is missing,
because missing code is not in the diff. Only the ticket says what should be there.

So this pass produces a **complete list**. Every requirement gets a row. If you skip one, it
still gets a row, marked skipped, with the reason. A list that silently drops items is worse
than no list, because it looks like coverage.

## Step 1 — Find the ticket

Take the ticket key from the PR title, branch name or body (`PROJ-1234`, `PROJ-123`, `LIN-12`).
A PR that names several tickets gets one table per ticket. A stacked PR ("part 2/4") covers only
its slice: read the stack comment or PR body to learn which slice, and mark the other parts
OUT OF SCOPE with the PR number that owns them.

Fetch, read-only:
- the ticket: description, acceptance criteria, attachments' text
- its subtasks and parent epic (scope often lives one level up)
- comments, newest first (decisions made after the description was written)
- linked tickets marked "blocks" / "is blocked by" / "relates to" (only their summaries)
- a local spec if one exists: `~/Downloads/<TICKET>/spec.md`

Locally use `acli jira workitem view <KEY> --fields '*all'`; in the cloud use the Atlassian
tools (`getJiraIssue`, `searchJiraIssuesUsingJql`). Never comment on, edit or transition the
ticket. If the ticket cannot be fetched, say so in one line and stop this pass.

## Step 2 — Enumerate

Build one list from everything in Step 1. One row per item, split compound sentences:

- **Requirements and acceptance criteria**: each "should", "must", "can", each bullet
- **Flows**: each user path the ticket describes, including error and empty states it names
- **Rules**: permissions, retailers, markets, feature flags, limits, dates
- **Decisions from comments**: "we agreed X instead of Y" replaces the description's Y
- **Non-functional asks**: translations, tracking events, migrations, docs

When the description and a later comment disagree, the comment wins. Note the conflict.

## Step 3 — Map each item to evidence

| Verdict | Means | Evidence required |
|---|---|---|
| **COVERED** | the PR implements it | `file:line` of the implementation, and the test that proves it if there is one |
| **PARTIAL** | some of it is there | what is there (`file:line`) and what is not |
| **MISSING** | nothing in the PR does it | what you searched for (grep terms, files read) |
| **OUT OF SCOPE** | belongs elsewhere | the other PR, subtask or comment that says so |

Rules:
- **Evidence over opinion.** A verdict without an artifact is not a verdict. Open the file; a
  name in the diff is not proof that the behaviour exists.
- **Label inference.** If the ticket is vague and you interpreted it, write the interpretation
  and mark the row *assumption*.
- **Search before MISSING.** The requirement may already be met by existing code the PR did not
  touch. Grep the concept, not the ticket's wording.

## Step 4 — Output

Show the table first (to the user, not to the author):

```
PROJ-4663 (part 2/4) — 9 items
  COVERED       5   months[] per range (ContractUsageService.cs:28, test :112) …
  PARTIAL       1   "quarterly view shows totals" — totals exist, preliminary tag missing
  MISSING       1   "range capped at 12 months" — grep Max/limit/AddMonths in Billing.API: none
  OUT OF SCOPE  2   period list UI → #4245
  assumption    1   "per month" read as calendar month (ticket says "monthly")
```

Then, for a review:
- each **MISSING** and **PARTIAL** becomes a finding on the closest line, `[should]` by
  default, `[must]` when it is an acceptance criterion. Quote the ticket line.
- COVERED and OUT OF SCOPE rows are never posted. They are for the reviewer.
- If everything is covered, post nothing from this pass.

## Never

- Never write to Jira.
- Never judge whether the ticket is a good idea — that is `ticket-refine`. This pass asks only
  whether the PR does what the ticket says.
- Never mark COVERED from the PR description alone. The description is a claim; the code is the
  evidence.
