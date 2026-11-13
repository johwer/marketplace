---
name: bridge-pre
description: 'Bridge (pre): before a plan is locked, send one compact brief to several independent advisors (different lenses, optionally different models) and synthesise where they agree, where they split, and what only one of them saw. Runs after grill-me or lift-the-gaze has laid out options. Use when the user says "bridge", "pre-bridge", "collab", "bolla med fler", "fråga andra modeller" or "second opinion on the plan", or when a lift-the-gaze decision is load-bearing. Not for reviewing a diff (that is review-pr).'
user_invocable: true
---

# Bridge — pre

More angles on a decision before it is made, at the lowest token cost that still gives a different view.

The value is in **disagreement**. Advisors who all agree confirm; an advisor who sees something the others missed is the reason to run this. The synthesis surfaces those; it never decides for the user.

## When not to run it

- The problem is not framed yet. Run `grill-me` or `lift-the-gaze` to the options stage first; a brief without options produces generic advice.
- The decision is already agreed with the user, PO or tech lead. Bridge does not reopen it.
- A 1-point ticket with one obvious option.

## Step 1 — Write the brief

Use `prompts/brief-template.md`. Write it to `.dream-team/bridge/brief.md` in a DTF worktree, otherwise to the session scratchpad.

Rules, all of them load-bearing:

- **No lean.** Options are labelled A/B/C in shuffled order, each stated at its strongest. No "we prefer", no recommendation, no order that hints. An advisor told the answer agrees with it.
- **Advisors cannot read the repo.** Put in what they need: the decision, constraints, standing decisions that apply (quote them), and code excerpts by `path:line`. At most ~150 lines of code and ~1500 words in total. Every extra line is paid once per advisor.
- **"Reuse what exists" is an option whenever one exists.** If `lift-the-gaze` ("Existing before new") or the code turned up a mechanism, field or flow that already does part of the job, it goes in as its own option with its `path:line`, and "do nothing / not needed" goes in when the need itself is in doubt. Eval 2026-11-10: the swarm found these necessity and reuse concerns 2–3 of 3 times when the brief named the alternative, while no PR reviewer found them (0 of 12 runs with repo access, with or without the team's skills). After implementation the question is too late; this brief is where it gets asked.
- **A permission or port decision carries its history.** Quote the legacy parity fact (what legacy granted, with file:line) and the permission's placement history (the ghost [PERMISSION-PLACEMENT] decision, the ticket that moved it). Without them advisors chose a new permission 5 of 7 times; legacy parity through lift-the-gaze flipped it (PROJ-4797).
- **No PII, secrets, customer or patient data.** Names become roles; real IDs become placeholders.
- Show the user the brief path and a three-line summary. Proceed unless they object.

## Step 2 — Run the advisors

```bash
bash ~/.claude/skills/bridge-pre/bin/advise-all.sh .dream-team/bridge/brief.md ~/.claude/skills/bridge-pre/variants/<variant>.conf .dream-team/bridge/advisors
```

Pick the size by how hard the decision is to undo (eval 2026-11-10, 12 cases × 2 runs, Sonnet grader, 31 expected findings):

| Size | When | Variant | Hits | Cost per pass over 12 |
|---|---|---|---|---|
| M (default) | most decisions | `haiku-7lens` | 28.0 | $0.17 |
| M+ | hard to undo: migration, ServiceC, events, data | `sonnet2-haiku5` | 28.5 | $0.72 |
| S | small, easy to change | `simplest` + `failure` only | ~26 (subset estimate) | ~$0.05 |

Bigger, smarter or doc-loaded swarms did not beat these; the numbers are in `eval/README.md`.

**Triage with a critic (Step 4).** `eval/critic-run.sh` runs a critic with no code access (default Sonnet; pass `claude-fable-5-2` for M+ when less noise is worth the extra cost) that merges duplicates and splits the points into a shortlist of at most 8 and a "weak" list. Show the shortlist first and the weak list collapsed, never dropped: about 30 % of the real findings land under weak. Per-model figures are in `eval/README.md`.

More lenses mean more noise, so Step 4's check against the repo matters. The automated verifier (`bin/verify.sh`) is not part of the flow. Keep the brief blind. Rerun the eval before changing any of this. Advisors answer a narrow lens question from a short brief, which is Haiku or Sonnet work; the critic and the synthesis run on the stronger model. Variant lines may add an effort level; each advisor is capped at `BRIDGE_MAX_USD_PER_ADVISOR` (default 0.50). It prints each advisor's cost and the total. Answers land in `.dream-team/bridge/advisors/<lens>@<model>@<effort>.md` (scratchpad outside a worktree).

Lenses live in `lenses/`. A variant file is lines of `<lens> <model>`. External providers (Codex, Gemini) are refused by `bin/advise.sh` until the company has approved sending code to them; that gate is deliberate, do not route around it.

## Step 3 — Escalate only on a load-bearing split

If advisors recommend different options **and** the difference changes what gets built, offer one tie-breaker: a single Opus or Fable advisor given the brief plus the two positions, asked "what fact decides between these?". Ask the user first; it is the expensive call. If they agree or the split is cosmetic, skip it.

## Step 4 — Triage, then synthesise (in this session)

Run the critic on the advisors' answers. It has no code access; it merges duplicates and splits the points into a shortlist (at most 8) and a weak list. Nothing is dropped.

```bash
bash ~/.claude/skills/bridge-pre/bin/critic.sh .dream-team/bridge/brief.md .dream-team/bridge/advisors .dream-team/bridge/critic/sonnet
```

Then read `.dream-team/bridge/critic/sonnet.json`. Before presenting any claim about the code, check it against the repo: advisors and critic saw excerpts only. Drop or correct what fails, and say so.

Present:

| | Vad | Vilka |
|---|---|---|
| Överens | shortlist points every advisor made | all |
| Splittrat | where recommendations differ, and the fact that would decide it | lens@model per side |
| Bara en såg | shortlist singletons, marked verified / unverified | lens@model |

Below the table, the weak list collapsed in one line each: about 30 % of real findings land there in the eval, so the user must be able to open it. Then the single question whose answer changes the plan most. The user decides. Report the total cost (advisors plus critic) in one line.

If the critic fails or times out, synthesise from the raw answers as before and say so.

## Step 5 — Record

Append the table, the user's decision and the cost to `.dream-team/bridge/log.md` (worktree). Cleanup (`workspace-cleanup` Step 5.5, `create-stories` teardown) runs `bin/archive-live.sh`, which copies `.dream-team/bridge/` to `~/.claude/bridge-eval/live/<TICKET>/` as a live eval case. The decision itself flows on through `lift-the-gaze`'s summary, `pr-decisions` or `ticket-spec`, not from here. Post nothing anywhere.

## Measuring which setup is worth it

`eval/README.md`: replay old tickets' pre-implementation briefs through each variant and score how many of the issues reviewers later raised each one surfaced, against cost. Change the default variant only on that evidence.
