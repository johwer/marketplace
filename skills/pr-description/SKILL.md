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

**Compose, never replace.** These are the top sections of a PR description, not the whole thing.
If the body already has detail sections, edit only the sections below and leave everything else
byte-identical — see "Writing it back". Applying this as a rewrite on a mature PR deletes most of
the body, including the pros/cons and verification tables other skills put there.

~200 words covers `## Why` + `## What changes` only — see "Word budget".

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

## Decisions            <- SLOT ONLY. This skill reserves the heading; `pr-decisions` writes the body.

<Include the heading only when a real judgement call was made, and ALWAYS when the
implementation diverged from what the ticket proposed. Do not write the content here —
invoke `pr-decisions` for it, so alternatives and trade-offs have one owner instead of two
skills producing overlapping prose. If the section already has content, leave it alone.>

## How to see it

<Screenshots for UI. Pasted command output for tooling and CI. The exact steps for
anything a tester would need to reproduce. If it genuinely cannot be observed, say why.>

## Not in this PR

<Scope boundary. What a reader might reasonably expect to be here and is not, plus where
it went — a follow-up ticket number, a held part, a deliberate omission. Omit this section
only if there is genuinely nothing to say, which is rarer than it feels.>

<!-- walkthrough, verification tables, screenshots and every other existing section
     continue below, untouched -->
```

## Workflow

1. **Read the ticket and the diff.** Not to summarise them — to find the gap between what was asked and what shipped. That gap is the most valuable sentence in the description.
2. **Write "What changes" first.** It is the hardest section and it disciplines the rest. If you cannot state a concrete outcome, you may not understand your own PR yet.
3. **Then "Why."** Once outcomes are on the page, the problem statement usually writes itself.
4. **Fill "How to see it" from evidence you actually have.** Never promise verification you did not do.
5. **Fill "Not in this PR" from the ticket's own scope.** Anything the ticket asked for that you did not do goes here, explicitly. So does anything you did that the ticket did not ask for — flag scope drift rather than letting a reviewer discover it.
6. **Read it back as the reader.** If you knew nothing about this work, would you know what changed and whether it is safe?
7. **Apply it without destroying the rest of the description.** See "Writing it back" below. This is not optional — most PRs you run this on already have a body.

## Writing it back — you own five sections, not the whole body

**The PR body is one field, and other skills write into it too.** A PR you run this on may already carry a reviewer walkthrough, captioned screenshots, a test guide and a progress checklist. Replacing the body with only your five sections destroys all of it. That has to be a deliberate act, never a side effect.

**Sections this skill owns:** `## Why`, `## What changes`, `## How to see it`, `## Not in this PR`, and the `## Decisions` slot (content delegated — see `pr-decisions`).

**Sections owned by others — never rewrite or drop:**

| Section (or equivalent) | Owner |
|---|---|
| `## Reading this diff`, `## Walkthrough of the changes`, per-file tables | `code-walkthrough` |
| `## Visual Verification Evidence`, any `<img>` block, `<details>` of superseded shots | `pr-screenshot-captions` |
| `## Decisions` body text | `pr-decisions` |
| Test-guide links / attachments | `tester-handoff` |
| `## Progress` checklist, anything the user wrote by hand | the user |

**Heading collisions.** Real PRs here usually open with `## Summary` rather than `## Why`. If a `## Summary` (or `## Overview`) exists, **replace it** with `## Why` + `## What changes` — do not append, or the PR ends up with two purpose sections saying the same thing differently. `## Not in this PR` and `## How to see it` likewise replace their existing counterpart rather than duplicating it. If a PR splits observation across several sections by audience — local repro, deployed verification, evidence — leave that split alone and treat them collectively as your "How to see it".

**Procedure:**

```bash
gh pr view <PR> --json body --jq '.body' > /tmp/pr-body.md
cp /tmp/pr-body.md /tmp/pr-body.backup.md          # cheap insurance; keep until verified
grep -n '^## ' /tmp/pr-body.md                      # inventory: what exists, who owns it
# ... splice your sections in, leaving every other section byte-identical ...
gh pr view <PR> --json body --jq '.body' > /tmp/pr-recheck.md
diff -q /tmp/pr-body.md /tmp/pr-recheck.md          # a browser edit mid-flight = reconcile, don't clobber
gh pr edit <PR> --body-file /tmp/pr-new-body.md
```

Then verify: section count did not shrink, `grep -c '<img'` is unchanged, and the sections you do not own read exactly as before.

**Writing a description from scratch is the easy case** — a brand-new PR with an empty body. Say so and write the whole thing. The rule above exists for every other case.

## Word budget

~200 words covers `## Why` + `## What changes`. That is the target, not a cap on the description as a whole — `## How to see it` and `## Not in this PR` sit outside it, and a full-stack PR that reversed a decision mid-flight will exceed it. When it does, that is the signal to move the reasoning into `## Decisions` via `pr-decisions`, not to compress it until it is unreadable.

## Rules

- **Plain language over jargon.** Names of your internal types mean nothing to a PO. "Users with read-only access" beats "principals lacking `TemplateEdit`".
- **State unchanged behaviour explicitly.** "No user-visible change" is one of the most reassuring things a reviewer can read — and one of the most alarming if it turns out to be false.
- **Quantify mechanical change.** A 5000-line whitespace diff must be labelled as such, or a reviewer will either waste an hour or rubber-stamp it.
- **Name the risk you would want named.** If one part is riskier than the rest, say which and why. Reviewers reward this; they do not punish it.
- **Never claim verification you did not perform.** "Verified on accept with an HR user" is a factual claim. If you only ran unit tests, say that.
- **Links, not retellings.** Reference the ticket, the incident, the prior PR. Do not reproduce them.
- **Write it before you think you are done.** The description often exposes that a part of the ticket was missed.

## Readability check — run this before posting

These are measurable, so check them rather than eyeballing. Thresholds are from plain-language
research (GOV.UK / Digital.gov / Australian Style Manual), which consistently finds that *higher*-
literacy readers prefer plain English most — it is not simplification, it is speed. One legal-language
study found 80% preferred clear English, and the preference **grew** with the complexity of the issue.
Your reviewers are the audience this helps most, not least.

| Check | Threshold | Why |
|---|---|---|
| Average sentence length | **15–20 words**, hard cap 25 | Long sentences carry the cognitive load that makes a reader skim |
| Ideas per paragraph | **one** | A reader scanning for "what changed" should not have to parse |
| Voice | **active** — "HR users no longer see the tab", not "the tab is no longer shown to HR users" | Names who does what; shorter by construction |
| Unexpanded acronyms | **zero**, minus the allowlist below | `TT`, `ServiceC`, `ServiceB`, `ORHI` are free to you and opaque to a PO |
| Internal type names in "Why" | **zero** | `CompanyAction.ProductContractsRead` belongs in the walkthrough, not the purpose |
| Unfalsifiable adjectives | **zero** | "cleaner", "more robust", "improved" — measure it or cut it |

**Acronym allowlist — do not expand these.** `API`, `URL`, `CI`, `CD`, `PR`, `HTTP`, `HTTPS`, `JSON`,
`HTML`, `CSS`, `SQL`, `UI`, `UX`, `ID`, `SDK`, `CLI`. Anyone reading a PR knows them, and forcing an
expansion produces worse prose — "a machine-readable description of each service" where "each API's
schema" was clearer. The rule targets **internal domain shorthand**, not industry vocabulary. If in
doubt: would someone at another company know it? Then it stays.

**Identifiers a reader can act on are not jargon.** "Zero internal type names in `## Why`" means class
and enum names — `CompanyAction.ProductContractsRead`, `SettingsMap`. It does **not** mean ticket keys
(`ITSM-19744`), customer names (Scania), environment names (accept), or the literal label the user sees
on screen ("the Products & Services tab"). Those are the most concrete things you can give a reader —
they make the description checkable. Name them.

Two quick tests that catch most of what the table misses:

- **The cold-read test.** Read only `## Why` and `## What changes`. If you knew nothing about this
  work, could you say what changed and whether it is risky? If not, the description is not done.
- **The stranger test.** Would someone from another team understand it? Not "could they infer it" —
  understand it, first pass, without opening the diff.

If a sentence needs a second read, split it. If a bullet needs a diagram, it belongs in the walkthrough.

Score it rather than guessing — write `## Why` + `## What changes` to a file and run:

```bash
python3 - draft.md << 'EOF'
import re,sys
t=open(sys.argv[1]).read()
prose=" ".join(re.sub(r'^[-*]\s+','',l) for l in t.split("\n") if l.strip() and not l.startswith("#"))
sents=[x for x in (s.strip() for s in re.split(r'(?<=[.!?])\s+',prose)) if x]
lens=[len(x.split()) for x in sents]
print("words %d | sentences %d | avg %.1f | longest %d | over cap %s"
      % (len(prose.split()), len(sents), sum(lens)/len(lens), max(lens),
         sorted([l for l in lens if l>25], reverse=True) or "none"))
EOF
```

Aim for avg 15–20 and nothing over 25. A dense three-paragraph summary typically scores ~25 average with outliers in the low thirties, which is exactly the version this skill is meant to replace.

## Common failure modes

- **Ticket paraphrase.** The description restates the ticket in slightly different words. Adds zero information.
- **Changelog.** A bullet per file or per commit. That is `code-walkthrough`'s job, and it belongs lower.
- **Silent scope drift.** The PR does something the ticket never asked for, and the description does not mention it. This is the one reviewers most resent discovering themselves.
- **Missing negative space.** No "Not in this PR", so a reviewer assumes the whole ticket is covered and approves an incomplete change.
- **Unfalsifiable claims.** "Improved performance", "cleaner code", "more robust" — with nothing to check. Either measure it or drop it.
- **Verification theatre.** "Tested thoroughly." Which users, which environment, what did you see?

## Worked example 1 — a user-visible change

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

## Worked example 2 — a PR with no user-visible behaviour

Most refactors, tooling and CI work land here, and it is where descriptions are weakest: with no user
to point at, people fall back to describing activity. The fix is the same rule — state what is now
**true** — but the subject is the system, not a person.

Ask: *what can the repo, the build, or the next developer now do (or no longer do)?*

```markdown
## Why

Regenerating an API client was manual, and nothing checked that a committed client still matched
its backend. Two ways to get this wrong had both already happened: regenerating against a stale
local container silently deleted members another PR had just added, and a committed client sat
behind its own backend for weeks because no one regenerated it.

## What changes

- Regenerating on a clean checkout now changes nothing. Any difference is drift, and the build
  says so instead of a reviewer noticing.
- A backend change that alters the API contract can no longer merge without updating the
  committed snapshot in the same PR.
- Client generation no longer reads from a running service, so output does not depend on what
  happens to be up locally.
- No runtime behaviour changes. This is build and CI only; no shipped code path is touched.

## How to see it

`npm run generate:api:service-c` on a clean checkout, then `git status` — output pasted below, no diff.
Second block shows CI failing on a deliberately hand-edited client, then passing once reverted.

## Not in this PR

- The minimum-client-version gate for mobile — NOVA-3448 Part 4, still open.
- The shared derivation copy — NOVA-3439, waiting on this.
```

What makes it work: every bullet is a *capability of the system* that changed. "Regenerating now
changes nothing" is an outcome; "added a CI check" would have been an activity. The fourth bullet
does real work — on a tooling PR, "no runtime behaviour changes" is the first thing a reviewer wants
confirmed, and stating it plainly is worth more than any amount of description elsewhere.

Note also that `## How to see it` is pasted command output, not screenshots. For tooling, the
evidence a gate actually fires is **showing it fail** — a check that has only ever been seen passing
has not been demonstrated to work.

## Related

- `pr-decisions` — the `## Decisions` section: choices made, alternatives, trade-offs. Use whenever the implementation diverged from the ticket.
- `code-walkthrough` — the file-by-file section for reviewers. Goes **below** this. Different audience.
- `pr-screenshot-captions` — captions the screenshots referenced in "How to see it".
- `tester-handoff` — the full test guide for a non-developer. Referenced from the PR, not inlined.
- `hook-then-detail` — when posting the PR to Slack, for the message that decides whether anyone clicks.
