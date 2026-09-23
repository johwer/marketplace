---
name: ticket-spec
description: Keep the implementation spec for a Repo ticket in a local markdown file at ~/Downloads/<TICKET_ID>/spec.md instead of in the Jira description, so Jira stays a short human summary and the detail an agent needs lives next to the ticket's screenshots. Use when writing or rewriting a ticket, when a subtask needs its parent story's goal and constraints, when scope changes mid-implementation and leftovers from the old shape may remain, or when a decision made in a session never made it into Jira. Covers the frontmatter contract (type, parent), how DTF hydrates the spec into .dream-team/jira-ticket.md, and the write-back back to Jira.
---

# Ticket spec files

Jira holds a **short summary a human can read** — what the ticket is, roughly. The
**spec file holds what is actually going to be built**: extracted requirements, the
endpoints and types involved, what is explicitly out of scope, and the decisions made
along the way. It lives at `~/Downloads/<TICKET_ID>/spec.md`, next to that ticket's
downloaded attachments and screenshots.

Everything below is driven by `~/.claude/scripts/ticket-spec.sh` — deterministic, no tokens.

```bash
ticket-spec.sh init <TICKET_ID> [--type story|subtask|spike|bug] [--parent <ID>]
ticket-spec.sh resolve <TICKET_ID>              # validate frontmatter + print parent chain
ticket-spec.sh hydrate <TICKET_ID> <WORKTREE>   # append spec + inherited parent into jira-ticket.md
ticket-spec.sh path <TICKET_ID>
```

## The frontmatter contract

```yaml
---
ticket: PROJ-3713
type: subtask          # story | subtask | spike | bug — required
parent: PROJ-3700      # required when type is subtask
goal: One line — what is true in the product when this is done
---
```

Sections, in this order: `## Goal`, `## Requirements`, `## Contracts`, `## Out of scope`,
`## Decisions`, `## Open questions`. The section names are load-bearing — `hydrate` extracts
`Goal`, `Out of scope` and `Decisions` from parents by exact heading.

**Never infer `type` from the Jira issue type.** Jira's issue type says how the ticket is
tracked; `type` here says how much context the work needs. Set it explicitly.

| `type` | What Jira holds | What the spec holds | How to treat it |
|---|---|---|---|
| `story` | The goal and why, for a PO or tester | Full requirements, contracts, out of scope | Full DTF run. The domain-model gate applies here, not in the children. |
| `subtask` | One or two sentences — "build the view with X", "wire the Y integration" | The requirements and APIs already extracted during refinement | Inherits the parent. Do **not** re-derive or re-litigate parent decisions; scope is this spec plus the parent's out-of-scope. |
| `spike` | The question being answered | What was tried and what it means | No implementation. The deliverable is an answer written into `## Decisions` and posted to Jira. |
| `bug` | Symptom and impact | Repro steps, and root cause once known | Reproduce with a failing test before fixing. |

## Create real Jira subtasks for work not yet started

For any new area or project, create the children as actual Jira **Subtasks** under their story,
so the parent relation is real in Jira and not only in these files. A Subtask carries a true
`parent`; two task-level items cannot, and the fallback is a `Relates` link that says the two
are connected but not which is above the other.

This is a rule for work not yet broken down. Where tickets already exist at task level, leave
them: re-parenting is not possible through `acli` (only `create` takes `--parent`, `edit` does
not), and the `parent:` field in these spec files carries the hierarchy the agents actually
read.

## Parent inheritance

A subtask read on its own loses the point of the work. `hydrate` walks `parent:` upward
(max depth 4, cycles are an error) and appends, for each ancestor, its **goal, out of scope
and decisions** — not its full spec, which would bury the actual task.

Those inherited sections are **binding**. A subtask may not quietly break a parent decision
or reach into the parent's out-of-scope; if the work requires it, stop and ask. Where spec
and parent genuinely conflict, surface it as a conflict rather than picking one.

If a parent has no local spec, hydration says so explicitly instead of staying silent — read
`acli jira workitem view <PARENT>` before assuming scope.

## When scope changes mid-implementation

This is what the spec is for, and skipping it is how leftovers survive: half-built code from
the shape the ticket had an hour ago, still there because nobody wrote down that it changed.

1. Update `spec.md` **first**, before changing code.
2. Add a dated line under `## Decisions`. Strike the superseded one through (`~~...~~`) —
   never delete it. A struck decision is the list of things to go looking for.
3. Re-run `hydrate` so the agents' source of truth matches.
4. Before going ready, diff the branch against `## Out of scope` and every struck decision.
   Anything the branch still does that those two lists say it should not is a leftover.

## Write it back to Jira

The spec is local: it is not in the repo, not in the PR, and no PO, tester or reviewer can
see it. So the ticket cannot be accepted from the spec alone.

At the PR-ready step, post the `goal` line plus any `## Decisions` added during
implementation as a Jira comment on the ticket. That is the write-back — without it, the
things worked out in a session stay in a file on one laptop, which is the gap this whole
pattern exists to close.
