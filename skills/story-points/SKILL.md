---
name: story-points
description: Estimate and set story points on Repo Jira tickets using the complexity-and-unknowns scale (1-4), where the number says how much is unresolved rather than how long it takes. Use when pointing a ticket or a batch of tickets, when asked to estimate, size or score work, during sprint planning or triage, or when a ticket needs its Story point estimate field set. Also covers writing the points to Jira, which acli cannot do.
---

# Story points — complexity and unknowns, not time

The number does **not** say how long something takes. It says how much is unresolved.
A large but completely understood change is a 1. A small change that first needs an answer
from someone is a 2.

| Points | Means | What to do with it |
|---|---|---|
| **1** | Just get going. Nothing to ask, nothing to decide — the work is understood end to end. | Put it in the sprint and work it. |
| **2** | Relatively easy, but **something has to be asked** before or during. One open question, one measurement, one decision that belongs to someone else. | Sprint it, and name the question in `## Open questions` so it gets asked early rather than discovered late. |
| **3** | Hard. Many unknowns, or it is really a **parent ticket that needs breaking down**. | A 3 is a signal, not a size. Break it down before committing to it; the children are usually 1s and 2s. |
| **4** | Does not exist. Something this big is an **epic**, not a ticket. | Never set a 4. If the work looks like one, it is an epic and needs stories under it. |

**A 3 is a finding.** Do not quietly point something a 3 and move on — say what would have to be
answered or split for it to become 1s and 2s, and offer the breakdown.

## How to estimate

Estimate against what is actually true, not what the ticket says:

1. **Read the spec file**, not only the Jira description — `~/Downloads/<TICKET_ID>/spec.md`.
   `## Open questions` is the single strongest signal: an empty one points toward 1, a question
   that blocks the approach points toward 2, several point toward 3. See the `ticket-spec` skill.
2. **Check whether work already exists.** A branch, a commit or an open PR can have resolved the
   very unknown the ticket is written around, which drops it a level. Check
   `~/Documents/<TICKET_ID>` and `gh pr list --head <TICKET_ID>` before estimating. A ticket
   whose description still poses a question the branch already answered is stale — correct it,
   and say so.
3. **Ask whether the question is inside or outside the team.** An unknown answerable by reading
   the code is not a 2; an unknown needing a person, a third party or a production measurement
   is.
4. **Name the reason in one line.** An estimate without a reason cannot be challenged.

## Writing points to Jira

`acli jira workitem edit` cannot set story points — it has no flag for custom fields, and its
`--assignee` path fails with "unexpected error" as well. Use the Atlassian Rovo MCP:

```
editJiraIssue(
  cloudId: "your-company.atlassian.net",
  issueIdOrKey: "PROJ-1234",
  fields: { "customfield_10437": 2 }
)
```

Project field ids: `customfield_10437` = Story point estimate, `customfield_10122` = Sprint (takes
the numeric sprint id, e.g. `3082` for Sprint 35).

One call per issue. Confirm the batch with the user before writing — points are a shared signal
in the sprint board, so setting them is an outward change, not a private note.

**A Subtask cannot be put in a sprint directly** — Jira rejects it with "underuppgifter kan inte
kopplas till en sprint" and it follows its parent instead. Set the parent's sprint; the children
land there. A PUT that mixes the sprint field with others fails as a whole, so set the assignee
in its own call rather than losing it to the sprint rejection.

**There is already a script for this — use it rather than hand-rolling curl:**

```bash
bash ~/.claude/scripts/jira-set-field.sh <TICKET_ID> customfield_10437 2
```

It handles the ACLI OAuth token from the macOS keychain and the cloud id, and its header
documents the known field ids. Loop it for a batch. Reach for the REST API directly only for
something the script does not cover.
