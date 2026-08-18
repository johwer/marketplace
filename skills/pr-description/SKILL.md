---
name: pr-description
description: Write the human-readable part of a PR description — why this exists, what is now true, and how to see it — for a reader who has not read the ticket or the diff. Use when opening a PR, when a PR description is just the ticket text restated or a list of files, when asked to "explain the purpose of this PR", or before handing a PR to a reviewer, PO, or tester. Covers the PURPOSE and OUTCOME; for the file-by-file reviewer walkthrough see code-walkthrough, and for captioning uploaded screenshots see pr-screenshot-captions.
---

# PR Description — purpose and outcome, for a human

Produces the top of a PR description: the part someone reads in **30 seconds** to understand why the PR exists and what it changed.

Audience: a colleague who has **not** read the ticket and will **not** read the diff. A PO checking it does what they asked. A tester deciding what to test. A reviewer deciding how much attention this needs. Your future self at the `git blame`.

## The one rule

**Never restate the ticket.** The ticket is one click away and the reader can already see the title. A description that paraphrases the ticket adds nothing and buries the part only you know: what the change actually *does*, and what it does *not* do.

Write what is true **after** this PR that was not true before.

## Outcomes, not activities

The single most common failure. An activity is what you did; an outcome is what is now different.

| Activity (weak) | Outcome (useful) |
|---|---|
| Added a permission check to the Products tab | Terveystalo HR users no longer see the Products & Services tab. Their deviant-rules and health-case tabs are unaffected. |
| Removed three feature flags | Three menu entries that no user could ever reach are gone. No user-visible behaviour changes. |
| Refactored the codegen setup | One command now regenerates a shared API client into both web and mobile. Previously each app had its own setup that had to be bumped in lockstep by hand. |
| Fixed the date picker | The date picker no longer overlaps the submit button on mobile. |

If a bullet could appear in a commit message, it is probably an activity. Push it down into the walkthrough and write the consequence instead.

## Shape

Keep the whole thing under ~200 words. Detail belongs below it, in the walkthrough.

```markdown
## Why

<1–3 sentences. The problem in the reader's language, not the code's. If there is a
reported incident, ticket, or customer, name it. If it is a refactor with no user-facing
symptom, say what it was costing — a hand-sync that keeps drifting, an undocumented
workaround, a silent failure mode.>

## What changes

<2–5 bullets. Each one a thing that is now true. User-visible where possible; otherwise
system-visible. Quantify when you can: "5450 lines reformatted, no semantic change" beats
"reformatted". If behaviour is unchanged, say so explicitly — that is a valuable claim.>

## How to see it

<Screenshots for UI. Pasted command output for tooling and CI. The exact steps for
anything a tester would need to reproduce. If it genuinely cannot be observed, say why.>

## Not in this PR

<Scope boundary. What a reader might reasonably expect to be here and is not, plus where
it went — a follow-up ticket number, a held part, a deliberate omission. Omit this section
only if there is genuinely nothing to say, which is rarer than it feels.>
```

## Workflow

1. **Read the ticket and the diff.** Not to summarise them — to find the gap between what was asked and what shipped. That gap is the most valuable sentence in the description.
2. **Write "What changes" first.** It is the hardest section and it disciplines the rest. If you cannot state a concrete outcome, you may not understand your own PR yet.
3. **Then "Why."** Once outcomes are on the page, the problem statement usually writes itself.
4. **Fill "How to see it" from evidence you actually have.** Never promise verification you did not do.
5. **Fill "Not in this PR" from the ticket's own scope.** Anything the ticket asked for that you did not do goes here, explicitly. So does anything you did that the ticket did not ask for — flag scope drift rather than letting a reviewer discover it.
6. **Read it back as the reader.** If you knew nothing about this work, would you know what changed and whether it is safe?

## Rules

- **Plain language over jargon.** Names of your internal types mean nothing to a PO. "Users with read-only access" beats "principals lacking `TemplateEdit`".
- **State unchanged behaviour explicitly.** "No user-visible change" is one of the most reassuring things a reviewer can read — and one of the most alarming if it turns out to be false.
- **Quantify mechanical change.** A 5000-line whitespace diff must be labelled as such, or a reviewer will either waste an hour or rubber-stamp it.
- **Name the risk you would want named.** If one part is riskier than the rest, say which and why. Reviewers reward this; they do not punish it.
- **Never claim verification you did not perform.** "Verified on accept with an HR user" is a factual claim. If you only ran unit tests, say that.
- **Links, not retellings.** Reference the ticket, the incident, the prior PR. Do not reproduce them.
- **Write it before you think you are done.** The description often exposes that a part of the ticket was missed.

## Common failure modes

- **Ticket paraphrase.** The description restates the ticket in slightly different words. Adds zero information.
- **Changelog.** A bullet per file or per commit. That is `code-walkthrough`'s job, and it belongs lower.
- **Silent scope drift.** The PR does something the ticket never asked for, and the description does not mention it. This is the one reviewers most resent discovering themselves.
- **Missing negative space.** No "Not in this PR", so a reviewer assumes the whole ticket is covered and approves an incomplete change.
- **Unfalsifiable claims.** "Improved performance", "cleaner code", "more robust" — with nothing to check. Either measure it or drop it.
- **Verification theatre.** "Tested thoroughly." Which users, which environment, what did you see?

## Worked example

A real one. The ticket asked for a new dedicated permission action; the PR shipped something simpler.

```markdown
## Why

A Terveystalo HR user at Scania could open Administration > Services and see the
Products & Services tab, which they are not entitled to (ITSM-19744). The tab had no
permission check at all — every other tab on that page was gated, this one was not.

## What changes

- HR users at Terveystalo no longer see the Products & Services tab.
- Their deviant-rules and health-case tabs are unchanged, and their day-to-day case
  work is unaffected — this was the main risk, since the same actions authorise both.
- The page itself is now driven by write actions rather than read actions, so holding
  a read permission for ordinary work no longer reveals an administration surface.
- No new permission action was added. Existing Create/Update actions were reused, so
  there is no migration and no seed-data change.

## How to see it

Screenshots below: as HR-pääkäyttäjä on TT accept, before and after. The tab is gone;
the other two tabs are still present. Also verified a user who should administer
products still sees it.

## Not in this PR

- The wider audit of which actions reveal which surfaces — NOVA-3440.
- The two platform-flag proxies — NOVA-3488.
- `ProductContractsRead` still gates the endpoint server-side; that is deliberate and
  unchanged.
```

Note what makes it work: the second bullet names the risk a reviewer would worry about
and answers it. The fourth pre-empts "does this need a migration?". "Not in this PR"
stops anyone assuming the whole overloading problem is solved.

## Related

- `code-walkthrough` — the file-by-file section for reviewers. Goes **below** this. Different audience.
- `pr-screenshot-captions` — captions the screenshots referenced in "How to see it".
- `tester-handoff` — the full test guide for a non-developer. Referenced from the PR, not inlined.
- `hook-then-detail` — when posting the PR to Slack, for the message that decides whether anyone clicks.
