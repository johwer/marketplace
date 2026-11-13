# DTF: --lite
Read when the arguments contain `--lite`.

The key principle: minimize agent overhead for small/medium tasks while keeping all quality gates, feedback loops, and process steps intact. Lite mode changes WHO does the work, not WHAT gets done. The "Rules for both full and lite mode" under Flags apply here too.

- **Phase 1 (Architecture)**: YOU do the analysis directly — don't spawn Amara. **First read `.dream-team/jira-ticket.md`** — the full Jira ticket and the source of truth (if missing, fetch and write it per Phase 1 step 2). Do NOT implement based on the command argument text alone; it may describe a proposed solution rather than the actual problem. Read the relevant docs, explore the codebase, determine scope, key files, and conventions, applying the Investigation rules (Phase 1). Produce the same architecture report format Amara would. **If `--interview` was used, read `.dream-team/interview.md` first** — the user's answers override ticket assumptions.
- **Lite Phase 1 reads the primitive table before copying a neighbour.** For every loading, error or
  empty state the change adds, use what `docs/FRONTEND_COMPONENTS.md` names (`QueryStateWrapper`),
  not the nearest file's `isLoading ? null`.
- **Phase 2 (Implementation)**: Based on complexity, decide:
  - **Simple** (1-3 files, single area): Implement directly yourself, no agents needed
  - **Medium** (4-8 files, single discipline): Optionally spawn 1 dev agent (Ingrid or Kenji)
  - **Complex** (8+ files, multiple disciplines): Spawn agents as needed — use your judgement
- **Phase 4 (Review)**: Review your own changes against conventions, or spawn Maya if the diff is large (10+ files). Always run the **Security Scan** (Section 7 of `dev-workflow-checklist.md`) — detect backend/frontend from `git diff --name-only origin/main` and run the applicable categories. Also run the Phase 4 reviewer checks yourself — Historical context lens (first), Stale RTK Query types (regenerate per "RTK Query API generation from worktree service", never an `as Parameters<...>` workaround), Dead redirect files, Business defaults at wrong layer — and fix what they find.
- **All other phases run as written:** 1.4, 1.5, 4.5 (if flagged), 4.75, 4.9, 4.95 (if `needs_feature_flag: true`), 5, 5.5, 6, 6.5 (write the summary yourself instead of spawning Tane), 6.75, 7.
- **Lite Phase 1 decides `needs_walkthrough: true/false`** (with a one-clause reason) in `.dream-team/notes/team-lead.md`, next to `needs_testing`. Set it true for a flow (several steps, a gate that opens, keyboard, focus, scroll) and false for static UI. `pr-body-gate.sh` refuses ready when a PR with .tsx changes never declared it.
- **Phase 4.75 (Visual verification)**: you drive the LIVE worktree app (port 31xx) with `playwright-cli`, check network + console, and save one screenshot per relevant state to `~/Downloads/<TICKET_ID>/` (never the repo, never `/tmp`), each taken as `bash ~/.claude/scripts/pw-mask-pii.sh <TICKET_ID>-lead && playwright-cli -s=<TICKET_ID>-lead screenshot ...`. No committed e2e specs or `toHaveScreenshot` baselines unless the user explicitly asks; a new component gets a Cosmos fixture (plus a unit test if it has interactive logic). Flow change → walkthrough video: `dev-workflow-checklist.md` Section 1.
  **If `pages/loginV2` changed:** read `~/.claude/docs/dtf-flags/mobile.md`.
- **Phase 6.75**: write your own retro learnings (same 4 categories and destination tags as Phase 6.75).
- **Phase 7**: as written (Completion Gate first); stops at Klart.
- **Phase 6.9 gate is mandatory in lite mode.** Before Phase 7, you MUST output completion markers for Phase 4 (review pass), Phase 4.75, Phase 6.75 and PR body assembly. No markers = Phase 7 blocked. See Phase 6.9 section.
- **Context management**: compact at phase boundaries per the `strategic-compact` skill.
- **Explicit phase gates in lite mode** (Explore → Plan → Implement → Commit):
  - **Explore** (research mode): Read the ticket, explore the codebase, understand the problem. Do NOT write code yet. Output: architecture report.
  - **Plan** (research mode): Present the implementation plan to the user. Wait for confirmation before proceeding. If the user says "just do it", skip the wait.
  - **Implement** (dev mode): Write code against the plan. Run build/tests after every meaningful edit.
  - **Review** (review mode): Phase 4 self-review.
  - **Commit** (dev mode): Run quality-gate.sh (it scopes prettier/eslint to changed files; never `prettier .` / `npm run writePrettier` by hand), de-sloppify, commit, push.
  Each transition is a natural compact point.

In full Dream Team mode, TeammateIdle and TaskCompleted hooks enforce Phase 4.75 and 6.75 automatically. In lite mode there are no named agents, so those hooks never fire. You must self-enforce here — explicitly.

**You MAY NOT enter Phase 7 until ALL FOUR markers below have been output in this session.**

---

**Marker 0 — Phase 4 (Review pass):**

Lite mode runs the same review pass as a team session; it has no Maya, so nothing else forces it.

Run **`/reviewing-changes` first** (root `AGENTS.md`; it edits code, so run it in this worktree,
one to three rounds), then a review pass over the diff it leaves — `/ghost-review` for backend, `/owl-review` for the
tech-lead lens, or the `pr-reviewer` subagent — **plus `/hard-simplify` always**, and the
`lift-the-gaze` Step 0.7 lens when the diff touches a contract or boundary. Output exactly:
```
✓ PHASE 4 COMPLETE (review pass)
  rc:       <reviewing-changes: N rounds, M fixed, K asked / "n/a — branch before #4470">
  ran:      <ghost-review | owl-review | pr-reviewer subagent — which, and on what diff>
  security: <security-relevant.sh first line> — security-review <ran: N findings | skipped (script said no)>
  simplify: <hard-simplify: N REUSE resolved / none>
  gaze:     <lift-the-gaze 0.7: findings / "n/a — no contract or boundary change">
  findings: <N> (<must-fix count> MUST FIX, <suggestion count> suggestions)
  resolved: <how each MUST FIX was handled, or "none found">
```

"Nothing found" is a legitimate result — but it must be the result of a pass that ran, not of a
pass that never happened. If you have not run a review pass — **STOP. Go do it now.**

---

**Marker 1 — Phase 4.75 (Visual Verification):**

If the ticket involved ANY `.tsx` / frontend changes, output exactly:
```
✓ PHASE 4.75 COMPLETE
  verification: lead drove the LIVE app via playwright-cli — network/console clean — PASSED
  evidence:     ~/Downloads/<TICKET_ID>/*.png  (real-browser shots — NOT committed)
  cosmos:       <fixture path if a new component, else "n/a">
  walkthrough:  <~/Downloads/<TICKET_ID>/walkthrough-<flow>.webm | "n/a — needs_walkthrough: false (<reason>)">  (walkthrough-required.sh must not print unset)
  committed:    none (git diff shows no repo screenshots / e2e baselines)
```

If the ticket had zero frontend/UI changes, output exactly:
```
✓ PHASE 4.75 SKIPPED — no UI changes
  Evidence: git diff --name-only origin/main shows no .tsx/.css files
```

If you have not yet done Phase 4.75 — **STOP. Go do it now. Then come back here.**

---

**Marker 2 — Phase 6.75 (Retrospective):**

Output exactly:
```
✓ PHASE 6.75 COMPLETE
  journal:    .dream-team/journal/lead.md — <N> entries written
  learnings:  dream-team-learnings.md — session entry appended
  history:    dream-team-history.json — session record added
```

If you have not yet done Phase 6.75 — **STOP. Go do it now. Then come back here.**

---

**Marker 3 — PR body assembly (`pr-ready` + body gate):**

The description a human actually reads is not optional in lite mode. Run `pr-ready` (after `pr-screenshot-captions`), then the gate, and output exactly — with the **real pasted gate output**, not a paraphrase:

```
✓ PR BODY ASSEMBLED
  skill:    pr-ready — body cut to the repo's shape (template: Summary / Visual verification / Considerations / Agent; dtf: Why / What changes / Visual verification / Scope)
  moved:    <walkthrough | decisions | verification | pre-emptive review | audit findings — or "nothing to move">
  comment:  <URL of the "Implementation notes — reviewer detail" comment, or "n/a">
  gate:     bash ~/.claude/scripts/pr-body-gate.sh <PR_NUMBER>
            <paste the actual output line, e.g. "✓ PR #3412 body: 174 words, no banned sections">
```

If the gate exits 1 — **STOP. Run `pr-ready` properly. Do not hand-edit around the gate**, and do not go ready.

---

**All four markers must appear in your output before you write the first line of Phase 7.** If any is missing, Phase 7 has been entered prematurely and the session is incomplete.
