---
name: grill-fe
description: Adaptive frontend grilling — reads the frontend conventions and the repo first, then asks one sharp question at a time (with a recommended answer) about ONLY what's genuinely unresolved. Run DURING a frontend ticket while building a component, page, or hook. Question count scales to the ticket; not the broad pre-ticket design interview.
autoTrigger:
  - when user says "grill-fe", "mini grill", or "grill me on this component/page/hook"
  - when starting frontend implementation on a ticket and the approach has open questions (which component to reuse, what states to handle, where the data comes from)
globs:
  - "apps/web/src/**/*.ts"
  - "apps/web/src/**/*.tsx"
---

# Grill FE — Mini Frontend Grilling

## Purpose

A **focused, adaptive** grilling pass for frontend work that runs **while you're already in the ticket** — you have a worktree, you have requirements, you just want a sharp gut-check before (or during) building. This is NOT the broad pre-ticket design interview (`/grill-me`) and NOT the backend domain-model grilling (`grill-with-docs`).

Goal: catch the frontend mistakes that cost a review round — missing states, reinventing an existing component, lost i18n, refresh-killing state, the wrong Tailwind token — in **as few questions as the ticket actually needs**. It resolves everything it can from the conventions and the code, and only asks about what's genuinely undecided. A trivial component might take 2–3 questions; a brand-new flow might take a dozen.

## What the User Provides

$ARGUMENTS

Treat arguments as the component / page / hook / feature being built. If none given, ask once: "What frontend thing are we building?"

## Protocol

**Recon first, conversation second.** Before asking the user a single question, do a silent pass: read the conventions AND explore the repo. Only once you know what the rules and the codebase already settle do you open the conversation — and then only on what's left. Never start interviewing cold.

**Conventions-first — read the rules before you ask anything.** Before the first question, load the frontend conventions from **wherever they live** — don't depend on a single path. Try in order, take the first that resolves:
1. **Project-level skill** in the repo — `.claude/skills/frontend-conventions/SKILL.md` (or `.claude/skills/frontend-conventions.md`). Auto-loads via globs when editing `apps/web/src/**/*.ts{x}`.
2. **Global skill** — `~/.claude/skills/frontend-conventions/SKILL.md`.
3. **Raw docs fallback** (older branch / neither skill present) — `docs/CODING_STYLE_FRONTEND.md`, `docs/FRONTEND_COMPONENTS.md`, `docs/TAILWIND_CONVENTIONS.md`, `docs/INTERNATIONALIZATION.md`.

The same applies to any backend/data conventions if the ticket touches them (project-level `.claude/skills/<x>-conventions/SKILL.md` → global → docs). **Anything the conventions settle is NOT a question** — apply it silently and move on (tabs → `useSearchParamTab`; never `defaultValue` in `t()`; `bg-warning` is red; never edit generated `*Api.ts`). The conventions are what make this grill short: they pre-answer a whole class of questions so you only ask about what's left.

**Codebase-first — explore before you ask.** If a question can be answered by reading the repo, answer it yourself and confirm, instead of asking blind. Check `apps/web/src/` for existing components/hooks, the relevant `*Api.ts` / `*ApiEnhanced.ts`, and the Tailwind token usage before posing the question.

**One question at a time. Each question carries a recommended answer. Wait for the response before advancing.**

**Adaptive — let the ticket set the length.** There is no target question count. After conventions + code, ask only about what genuinely changes what you'd type. A trivial component may need 2–3 questions; a brand-new flow may need a dozen. **Stop when no open decision remains that would change the implementation** — stop at that condition, not at a number. If you surface a genuinely upstream design gap (data model, API contract, scope), stop and recommend `/grill-me`; that's the right tool for that, not this one.

## Question Checklist (skip what's already answered)

Work through these, codebase-first, one at a time:

1. **Data source** — Where does the data come from? Which RTK Query endpoint? Is the generated `*Api.ts` enough, or is an `*ApiEnhanced.ts` override / temporary `injectEndpoints` type needed because the backend isn't stable yet?
2. **Loading / empty / error states** — Are all three handled? Is there an existing empty-state / skeleton / error component to reuse rather than rolling a new one?
3. **Reuse vs. new** — Does a component or hook already exist for this? Explore `apps/web/src/` first; propose the reuse, only build new if nothing fits.
4. **State persistence** — Does any state (tabs, filters, selection) need to survive a refresh or be shareable via URL? If tabs → `useSearchParamTab`, not `useState`.
5. **i18n** — Any new user-facing strings? Reminder: no `defaultValue` in `t()`; create keys in all 5 languages (en, sv, da, no, fi); dynamic enum keys use `t(\`prefix_${value}\`)` and must be added to `scripts/lokalise_whitelist.json`. Commonly missed: empty states, dialogs, table headers, dropdown labels.
6. **Tailwind tokens** — Is the right semantic token being used? Flag the trap: `bg-warning` is **red**, not yellow. Confirm intended color matches the token.
7. **Responsive / edge** — Mobile viewport, long/overflowing content, null/zero rows, very large lists.
8. **Visual proof** — Plan a screenshot into `__screenshots__/` next to the component before marking done. Verbal "verified" is not enough.

## Output — no menu

There is **no** "pick an output: ticket / PRD / arch-plan" step. You already have the ticket. When the grill is done:

- **Write the resolved decisions back to the ticket** (or the worktree notes if in a Dream Team session) so requirements aren't lost — a short decision log: what was decided and why, plus any open risk.
- Then **hand straight back to implementation.**

If grilling surfaced an upstream design gap that a mini grill can't resolve, say so and point to `/grill-me`.

## Style

- One question per turn, each with a recommended answer to react to.
- Explore the repo before asking; confirm findings rather than interrogating blindly.
- Be quick and surgical — this is a gut-check, not a design review.
