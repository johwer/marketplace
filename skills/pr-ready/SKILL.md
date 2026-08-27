---
name: pr-ready
description: Assemble a Repo DTF pull request body at the ready transition — cut it down to the four sections a human actually reads (Why, What changes, Visual verification, Scope) and move all reviewer detail into a single "Implementation notes" comment below the diff. Use immediately before `gh pr ready`, when a PR description has grown into a wall nobody reads, or when the pr-body-gate script refuses. Repo/DTF only — not for personal-project PRs.
---

# PR Ready — cut the body down to what a human reads

Repo DTF only. Runs once, immediately before `gh pr ready`.

## The problem this exists for

Six skills each write a well-behaved section into one text field. Every section is individually
justified. The sum, measured across eight merged PRs, is **a median of 1,700 words and 13
headings** — an eight-minute read *before* the diff. Reviewers don't start there. They skim, or
they skip the description and review the wrong file, or they close the tab.

Nothing in the flow was violated to produce that. There was just no owner for the *whole* body.
This skill is that owner, and it owns it at exactly one moment: the ready transition.

## The one rule

**The body is for the human deciding whether and how to look. The comment is for the reviewer
who has decided to.**

Anything that answers "should I care, and what am I looking at" stays in the body. Anything that
answers "how does it work, and did you check X" goes below the diff, where the reader who wants
it will scroll and the reader who doesn't is unaffected.

## Target shape — four sections, ~180 words, 250 hard cap

```markdown
## Why

<2–3 sentences. The problem in the reader's language. Name the customer, incident or
ticket if there is one.>

## What changes

- <max 4 bullets, each a thing that is now TRUE that was not before>
- <outcomes, not activities — see the pr-description skill for the distinction>
- <if behaviour is unchanged, say so explicitly; that is a valuable claim>

## Visual verification

<captioned before/after images — pr-screenshot-captions owns this section's content>

## Scope

Not covered: <one line>. Follow-up: NOVA-XXXX.
Test guide: NOVA-XXXX Jira comment.
```

Image captions do not count toward the budget. Neither does anything inside `<details>`.

## Keep, move, drop

| Section | Action |
|---|---|
| `## Why`, `## What changes` | **keep** — trim to budget if over |
| `## Visual verification` / `## Visual Verification Evidence` + all images | **keep**, byte-identical |
| `## Scope` / `## Not in this PR` | **keep**, compressed to one line + follow-up ticket |
| `## Walkthrough of the changes`, `## Reading this diff`, per-file tables | **move** |
| `## Decisions` (resolved) | **move** as one line each: `Chose X over Y because Z` |
| `## Verification`, `## Runtime verification`, `Verified, not assumed` | **move** |
| `## Pre-emptive review`, ghost/owl findings, `One suggestion deliberately not taken` | **move** — this is what buys off a review round; do not lose it |
| `## What the audit turned up`, `## Also landed, beyond the ticket's ask`, `## Pre-existing issues found` | **move** |
| Long enumerations — `## All 40 bumps`, dependency tables, `## Deliberately left behind` | **move** |
| `## How to Test`, `### Prerequisites`, `### Steps`, `### What to Look For` | **drop** — replaced by the one-line `Test guide:` pointer |
| `## Progress` checklist | **drop** — 100% checked and worthless by the time a human reads it |
| `## Architecture` (scope / agents / key files) | **drop** — a session artifact, not reader-facing |
| `## Questions` (answered, or `_No open questions yet._`) | **drop** |
| `## Decisions` (still **open** — an unanswered domain-model gate) | **keep in the body** — see below |
| The ASCII `DREAM TEAM` banner | **drop** |
| Anything the user wrote by hand, any unrecognised heading | **move** — never drop |

### `## Decisions` is a working-stage instrument

While a domain-model gate is open, `## Decisions` belongs in the body — that is the whole point
of putting the question on GitHub where colleagues can weigh in. Once the decision is made, the
question is dead weight and the code is the answer.

So: **open decision → stays in the body. Resolved decision → one line in the notes comment.**
The record survives (you will want it when someone asks in three months why the column landed
where it did), it just stops costing 400 words above the fold.

## Safety — this is the only destructive write in the flow

Every other PR skill is told *compose, never replace*. This one deletes, and the screenshots you
drag-dropped live in the body interleaved with what it deletes. Four rules make it fail safe
rather than fail correct:

1. **Unknown headings are moved, never deleted.** A heading a future skill invents ends up in
   the comment (harmless), not destroyed (unrecoverable).
2. **Any line containing `<img` or `![` stays in the body**, regardless of which section it sits
   under. Image placement is not recoverable from the GitHub asset URL alone.
3. **Refuse the write if the image count dropped.** Compare before and after; if it fell, stop
   and report rather than writing.
4. **Re-fetch and diff immediately before writing.** The body is one text box and the user may
   be editing it in the browser. A mid-flight change means reconcile, never clobber.

## Procedure

```bash
PR=<number>
gh pr view "$PR" --json body --jq '.body' > /tmp/pr-body.md
cp /tmp/pr-body.md /tmp/pr-body.backup.md          # keep until verified
grep -n '^#\{1,4\} ' /tmp/pr-body.md               # inventory: classify every heading
IMG_BEFORE=$(grep -c -e '<img' -e '!\[' /tmp/pr-body.md || true)
```

1. **Inventory and classify.** Every heading goes into keep / move / drop using the table above.
   An unrecognised heading is a **move**, not a judgement call.
2. **Write the new body** to `/tmp/pr-new-body.md` — the four sections, in order, images
   byte-identical. Trim `Why` and `What changes` to budget; do not compress them into jargon to
   hit a number, move detail out instead.
3. **Write the notes comment** to `/tmp/pr-notes.md` (format below).
4. **Verify before writing anything:**
   ```bash
   IMG_AFTER=$(grep -c -e '<img' -e '!\[' /tmp/pr-new-body.md || true)
   [ "$IMG_AFTER" -ge "$IMG_BEFORE" ] || { echo "REFUSING: image count dropped"; exit 1; }
   gh pr view "$PR" --json body --jq '.body' > /tmp/pr-recheck.md
   diff -q /tmp/pr-body.md /tmp/pr-recheck.md || { echo "body changed mid-flight — reconcile"; exit 1; }
   ```
5. **Post the notes comment first, then shrink the body.** In that order: if step 6 fails, the
   detail is already safely on GitHub rather than only in `/tmp`.
   ```bash
   # Edit the existing marked comment if there is one — never append a second
   CID=$(gh api "repos/{owner}/{repo}/issues/$PR/comments" \
          --jq '.[] | select(.body | contains("pr-ready:notes")) | .id' | head -1)
   if [ -n "$CID" ]; then
     gh api -X PATCH "repos/{owner}/{repo}/issues/comments/$CID" -F body=@/tmp/pr-notes.md
   else
     gh pr comment "$PR" --body-file /tmp/pr-notes.md
   fi
   gh pr edit "$PR" --body-file /tmp/pr-new-body.md
   ```
6. **Run the gate, and show the operator the output:**
   ```bash
   bash ~/.claude/scripts/pr-body-gate.sh "$PR"
   ```
   Only then `gh pr ready "$PR"`.

## The notes comment

One comment per PR, carrying the marker so re-runs edit rather than append:

```markdown
<!-- pr-ready:notes -->
## Implementation notes — reviewer detail

_Moved out of the description so it stays readable. Nothing here is required reading to
review the diff._

### Walkthrough of the changes
<from code-walkthrough>

### Decisions made
- Chose <X> over <Y> because <Z>. Cost accepted: <cost>.

### Verification performed
<what was actually run, and on what — never a claim you did not perform>

### Reviewed pre-emptively
<ghost/owl findings and the ones deliberately not taken, with the reason>

### Found but not fixed here
<audit findings, pre-existing bugs, anything beyond the ticket's ask + follow-up tickets>
```

Omit any subsection that has nothing in it. A comment with two subsections is a good comment.

## Ordering — what must have run first

- **`tester-handoff` runs BEFORE this skill.** It reads the body's `## How to Test` as one of its
  inputs, and this skill deletes that section. Reverse the order and the test guide loses source
  material. (`tester-handoff` already writes to Jira, not the body — nothing to retarget.)
- **`pr-screenshot-captions` runs BEFORE this skill**, so the images are already grouped and
  captioned when the body is assembled.
- **`code-walkthrough` writes straight into the notes comment** in the DTF flow, so its output
  never enters the body in the first place.

## Failure modes

1. **Compressing instead of moving.** Squeezing 1,700 words into 250 produces dense,
   acronym-heavy prose that is *worse* than the wall. Move it; don't crush it.
2. **Deleting an unrecognised section** because it looked like scaffolding. Move it.
3. **A second notes comment on every re-run.** Use the marker and PATCH.
4. **Shrinking the body before posting the comment**, then hitting an API error — the detail
   exists only in `/tmp` and the operator has no idea.
5. **Dropping an open domain-model question** because `## Decisions` is on the move list. Check
   whether it is answered first.
6. **Running it on a draft mid-session.** The working sections are load-bearing while agents are
   still writing. This runs once, at ready.

## Related

- `pr-description` — writes `## Why` and `## What changes`; owns their content, not the body shape
- `pr-decisions` — writes the decision entries this skill relocates once they are resolved
- `code-walkthrough` — targets the notes comment, not the body
- `pr-screenshot-captions` — owns everything under `## Visual verification`
- `tester-handoff` — owns the test guide, in Jira
- `scripts/pr-body-gate.sh` — the fail-closed check; DTF Phase 6 and the Completion Gate both run it
