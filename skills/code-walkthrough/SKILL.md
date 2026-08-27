---
name: code-walkthrough
description: Explain the CODE changes of a branch or PR in plain prose, file by file, so a reviewer knows what to actually look at. Separates hand-written production code from tests and generated output (a 2000-line diff is often 200 lines of real change), and states scope honestly when part of the diff is not what the ticket asked for. Use when writing or improving a PR description, when asked "explain the changes / what actually changed / walk me through the diff", or before handing a branch to a reviewer. Not a test guide — see tester-handoff for that.
---

# Code Walkthrough — explain the diff, simply

Produces a **"Walkthrough of the changes"** section for a PR description (or a chat answer). Audience: a developer reviewer who has not read the diff and wants to know *where to look and why*.

The goal is to answer, in under a minute: **how much real change is there, which files matter, and is any of it not what the ticket asked for?**

## The one rule that makes this useful

**Split the diff into hand-written production code / tests+fixtures / generated output, and lead with those numbers.**

A "1,890 insertion" diff that is 75% tests is a small change wearing a big number, and a reviewer who doesn't know that budgets their attention wrongly. Equally, 200 lines of hand-written change hiding inside a 2,000-line generated diff needs surfacing. Get the numbers first — never estimate them.

```bash
git diff --numstat origin/main..HEAD | awk '
{add=$1; del=$2; f=$3;
 if (f ~ /\.test\.|\.spec\.|fixtures|__tests__|Test\.cs|IntegrationTests/) {t+=add; td+=del; tf++}
 else if (f ~ /rtk-apis|\.generated\.|Migrations\/|swagger/) {g+=add; gd+=del; gf++}
 else {p+=add; pd+=del; pf++}}
END {
 printf "hand-written production: %d files, +%d/-%d\n", pf, p, pd
 printf "generated:               %d files, +%d/-%d\n", gf, g, gd
 printf "tests + fixtures:        %d files, +%d/-%d\n", tf, t, td
}'
```

Adjust the patterns to the repo. Sanity-check the split against `git diff --stat` — if a file lands in the wrong bucket the headline number lies.

## Workflow

1. **Confirm the diff base.** `git rev-list --count HEAD..origin/main` — if the branch is behind, `git diff origin/main..HEAD` renders *main's* new work as deletions on your side and the walkthrough will describe files nobody touched. Rebase or use the merge base first. **Never take the base from a session preamble or a remembered SHA** — re-derive it.

2. **Get the split** (above), then `git diff --stat origin/main..HEAD` for the per-file picture.

3. **Read the actual diff of every hand-written production file.** Not the stat, the diff. For a new file, read the whole thing and work out what proportion is *data* (tables, config, constants) versus *logic* — "215 lines, of which 90 are a rule table" is far more informative than "215 lines".

4. **For each file, write one short paragraph**: what changed, and *why it had to*. Prefer the reason a reviewer couldn't guess. `useMemo` is not "for performance" if it's there because the value is an effect dependency — say that.

5. **Say what did NOT change, when that's the load-bearing fact.** "No consumer changed, because the shape is identical" tells a reviewer more than any list of what did change. If N files could plausibly have needed edits and didn't, that's the headline.

6. **State scope honestly.** If part of the diff isn't what the ticket asked for — an opportunistic fix, a pre-existing bug fixed in passing, endpoints that rode along in a regeneration — say so explicitly, with a rough line count. Reviewers find these anyway; finding them unannounced reads as scope creep, and finding them labelled reads as diligence.

7. **Write it where the reader who wants it will find it.**

   **In the Repo DTF flow: into the `Implementation notes — reviewer detail` comment, not the PR body.** The walkthrough is mechanism — it answers "how does it work", which is what a reviewer who has already decided to review wants. Putting it in the description pushes the purpose and the screenshots below the fold, and `pr-ready` will relocate it at the ready transition anyway. Write it to the comment directly and skip the round trip:

   ```bash
   CID=$(gh api "repos/{owner}/{repo}/issues/<PR>/comments" \
          --jq '.[] | select(.body | contains("pr-ready:notes")) | .id' | head -1)
   # append under "### Walkthrough of the changes" in that comment, or create it — see pr-ready
   ```

   **Outside DTF (or when asked for it in the description):** into the PR body under `## Walkthrough of the changes`, after the summary and before the evidence/testing sections.

   Either way, re-fetch immediately before writing (`gh pr view <N> --json body`, or re-read the comment) and diff against what you last read — the field is one text box and a concurrent edit is last-write-wins.

## Shape

Numbered bold paragraphs, one per file, biggest first. Prose, not bullet soup — a reviewer reads this top to bottom.

```markdown
## Walkthrough of the changes

**3 hand-written files, +288/−19.** Tests and fixtures are 1,389 lines — 75% of the diff.
The generated client is another 246. Less production code than the line count suggests.

**1. New — `utils/thing.ts` (215 lines).** The only new logic, and most of it is data
rather than code: ~90 lines are the rule tables, ~25 the evaluator, ~20 the assembly.
Typed against the generated type, so a backend rename fails to compile rather than
silently producing `undefined`.

**2. `routes/Guard.tsx` — four changes.** [one clause each, then:] Nothing else in the
file moved — the deliberate "do NOT gate on isLoading" logic is untouched.

**What keeps it small: no consumer changed.** ~38 files read this off context; the shape
is identical, so only the source moved. Needing to edit a consumer would have meant the
shape drifted.

**Scope note:** items 2 and 3 are *not* part of the swap — they fix a pre-existing bug,
about 30 of the 45 edited lines. A pure swap would have been ~15.
```

## Rules

- **Plain prose, no jargon-for-its-own-sake.** This is for a developer, so `useMemo` and `RTK Query` are fine — but explain *why* a change was needed, never restate what the diff already shows.
- **Never describe a file you have not opened.** Filenames and stats mislead; a "renamed" file can hide a rewritten body.
- **Distinguish data from logic** in new files. It changes how a reviewer reads them.
- **Don't editorialise about quality.** No "cleanly implemented", "nicely typed". Describe, and let the reviewer judge.
- **Don't pad.** If a file is a 9-line cache-tag addition, that's one sentence.
- **Generated files get one line** saying they're generated and not hand-authored — but if a regeneration pulled in anything unrelated, say what and why (see step 6).

## Common failure modes

1. **Quoting the raw insertion count as if it were the size of the change.** The single most misleading thing you can write.
2. **Computing the diff against a stale base**, so the walkthrough lists files from other people's tickets. Check `HEAD..origin/main` is 0 first.
3. **Trusting `--stat` instead of reading the diff**, and so missing that a "small" edit changed a condition's meaning.
4. **Burying the opportunistic changes.** A reviewer who finds an unannounced extra fix stops trusting the rest of the description.
5. **Omitting what didn't change.** Often the strongest evidence the change is contained.

## Related

- `tester-handoff` — the non-developer test guide. Different audience, no code references.
- `pr-screenshot-captions` — captions the visual evidence.
- This pairs with DTF `my-dream-team` Phase 5, where the PR description is written.
