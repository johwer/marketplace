---
name: hard-simplify
description: A blocking simplification pass on your own branch or someone else's PR. Reads the whole region a change lands in — not the diff hunks — and asks what the change makes deletable, not whether the added lines are tidy. Classifies every block as REUSE (file:line) / DELETE / KEEP, and only REUSE blocks the push, because only REUSE can point at existing code. Use before going ready, and when reviewing a PR for "could this have been fewer lines".
user_invocable: true
---

## Two rules that make this different from a nudge list

**1. The unit is the region, not the hunk.** `git diff -U3` shows you the added lines and
nothing they could have reused. The duplicate is almost always in code that is not in the
diff. So read the whole file the change lands in, and its siblings in the directory, before
judging a single line.

**2. Only a claim with a `file:line` may block.** "This feels long" is taste and gets scrolled
past. "`useTableSort` at `hooks/useTableSort.ts:14` already does this" is falsifiable, and a
gate can be built on it. Everything else is advisory and must be labelled as such.

The target is **negative**: not "are the added lines minimal" but **what does this change make
deletable**. Every change must name at least one thing it removes, or say explicitly "none,
because X".

---

## Step 1 — Deterministic first, always

Never spend model tokens on something a script can count.

```bash
bash ~/.claude/scripts/comment-gate.sh          # every added comment, in one list
cd apps/web && npm run lint && npm run type-check
```

The comment gate exists because "remove the comments" used to take four passes. It lists all
of them with `file:line` so the fix is one pass. Fix everything it prints before reading on.

## Step 2 — Read the region

```bash
git diff --stat main...HEAD
git diff --name-only main...HEAD
```

For each changed file: read the **whole file**, then `ls` its directory and read the siblings
that share a prefix or a concept. Grep the *concept* the change introduces — not the name you
gave it — across `apps/web/src/hooks`, `apps/web/src/ui`, `apps/web/src/utils` and the
service's `Domain/`. A helper that already exists under a different name is the single most
common finding, and the only one that blocks.

## Step 3 — Classify every block

Three verdicts, no fourth. State the line count for each.

| Verdict | Means | Blocks? |
|---|---|---|
| **REUSE** `path:line` | equivalent code already exists — the new block goes | **yes** |
| **DELETE** | the change makes this obsolete: a branch now unreachable, a prop nothing passes, a helper with one caller that could be inlined, a test asserting what a type now guarantees | no, but must be actioned or defended |
| **KEEP** | genuinely new, with the reason in one clause | no |

Anything you cannot put in one of the three has not been understood yet.

## Step 4 — Report a number

A verdict without a number is an opinion. End with exactly this:

```
340 rader netto (+410 / −70)
  REUSE   190 rader duplicerar hooks/useTableSort.ts:14        ← blockerar
  DELETE   40 rader — SortableHeader.tsx blir oanvänd
  KEEP    180 rader — ny endpoint + dess test
  Gör raderbart: pages/reports/sortState.ts (hela filen, 62 rader)
```

If the "gör raderbart" line reads *none*, say why in one clause. A change that adds code and
makes nothing removable is normal for a genuinely new feature and suspicious for anything else.

## Step 5 — Verdict

**REFUSED** while any REUSE line stands. Apply it or show why the existing code cannot serve —
"it is in another module" is not a reason, moving it is cheaper than duplicating it.

Everything else is advisory: list it, offer to apply it, and let the author decide.

---

## Reviewing someone else's PR

Same pass, one difference: only REUSE findings become review comments. A DELETE or KEEP
observation on someone else's branch is noise unless they asked. Post each REUSE as an inline
comment naming the existing `file:line` — that is a comment the author can act on in a minute,
and it is the whole answer to "could this have been written with fewer lines".

`/code-review --comment` posts them; this skill decides what deserves to be posted.

## Never

- Do not put the output in the code. Findings go in the terminal, decisions go in the PR body.
  A simplification pass that adds comment lines has made the file longer.
- Do not remove `useMemo` / `useCallback` / `React.memo` as "cleanup". The React Compiler is
  **not** enabled in this repo; memoization is manual and load-bearing.
- Do not count generated files, snapshots or lockfiles in the numbers. State them separately.
