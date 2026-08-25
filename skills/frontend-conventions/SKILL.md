---
name: frontend-conventions
description: Frontend coding conventions for the Repo monorepo
---

## Loading Conventions

Project-level conventions are loaded automatically via `.claude/skills/frontend-conventions.md` when editing `apps/web/src/**/*.ts{x}` files.

If project-level skills are not available (e.g., older branch), read these files directly:
- `docs/CODING_STYLE_FRONTEND.md`
- `docs/FRONTEND_COMPONENTS.md`
- `docs/TAILWIND_CONVENTIONS.md`
- `docs/INTERNATIONALIZATION.md`

## DTF Supplements

These patterns come from team experience and are not in the project-level skills:

### i18n — Hard-Learned Rules
- **Never use `defaultValue`** in `t()` calls — it masks missing keys in production.
- **Dynamic keys from enums**: use `t(\`prefix_${enumValue}\`)` and add the pattern to `scripts/lokalise_whitelist.json`.
- Use `toBackendLanguage()` from `i18n.ts` when sending language to API calls (`"key"` → `"en"`).
- Commonly missed: empty states, confirmation dialogs, table headers, dropdown labels.
- TranslationService API workflow: create keys with ALL 5 languages (en, sv, da, no, fi). S3 sync is automatic via CI.
- **Concise UI copy (flag verbose labels in review).** Copy pasted straight from mockups makes long strings that get translated ×5. Flag: (a) action labels longer than ~1–2 words when the dialog/page context already conveys meaning — a modal's primary button should be `Apply`/`Add`/`Save`/`Finish`, not a full sentence; (b) a counter/value fused into a label (`"{{count}} companies selected"` as one key) — the count belongs in a separate element, the action label stays short/reusable (`common_apply`). Prefer `common_*` keys for ubiquitous actions. Ref: INTERNATIONALIZATION.md "Concise UI copy".

### Tab State
- Use `useSearchParamTab` hook for tab components, not `useState`. Tab state must survive page refresh and be shareable via URL.

### RTK Query — Enhanced Files
- `*ApiEnhanced.ts` files add cache tags and manual endpoint overrides.
- When backend isn't stable yet, add temporary types in Enhanced files with `injectEndpoints`.
- After regenerating, check if Enhanced overrides can be removed.

### Generated Files
- `*Api.ts` in `src/store/rtk-apis/` are auto-generated. Never edit directly.
- `*BaseApi.ts` are manually maintained base API definitions.
- Use `/generate-api` to regenerate from backend Swagger specs.

### Cosmos Fixtures
- **New or meaningfully-changed visual components should get a Cosmos fixture** in `apps/web/src/fixtures/RetailerBranded/` (`react-cosmos` 7.3.0; run with `npm run cosmos`).
- Follow the nearest sibling as a template (e.g. a new `DocumentationNoteRow` mirrors the existing `EmployeeDocumentRow.fixture.tsx`). If an analogous component is already fixtured, the new one should be too.
- Fixtures give an isolated render, so they're also the cheapest way to produce visual proof when the full flow can't run locally (no backend, blocked click-through).

### Visual Verification
- `__screenshots__/` captures are for **e2e tests and your own local verification** — they are **not** a hard PR gate. Don't block a PR on a missing `__screenshots__/` folder.
- **The PR gate is a screenshot in the PR description.** When reviewing, if the description has no screenshot, **ask the author to add one** rather than flagging a missing local screenshot dir.
- Verbal "verified" is not enough — a screenshot (in the PR description, or a Cosmos fixture render) is the proof.

### Dates — use `utils/date.ts`, never raw `new Date()` / bare date-fns

`apps/web/src/utils/date.ts` (~680 lines) is the canonical date layer. Reaching past it into `date-fns`
or `new Date(str)` is how the same timezone bug keeps coming back — it was fixed in NOVA-3062 and
reintroduced in NOVA-3382.

**Parsing.** `getDateWithoutTzConversion(str)` — strips a trailing `Z`, and parses date-only strings
(`"2026-02-13"`) as **local** midnight. Raw `new Date("2026-02-13")` parses as **UTC** midnight, which
renders a day early at negative offsets (Americas). But full timestamps (`...T12:25:00Z`) must parse
natively — stripping `Z` shifts times for positive-offset (Nordic) viewers. One strategy cannot serve
both: branch on date-only vs timestamp, which is what the helper does.

**Day boundaries.** `getStartOfDate("days", date)` / `getEndOfDate`. Comparing an absolute instant
against a local `startOfDay` mixes frames:

```ts
// wrong — instant vs local midnight; flags today's item as overdue at UTC-1 or below
isBefore(new Date(plannedAt), startOfDay(new Date()))

// right — day vs day, both through the shared layer
isBefore(getStartOfDate("days", getDateWithoutTzConversion(plannedAt)), getStartOfDate("days"))
```

**Display vs wire.** Display uses each locale's national format via date-fns `P`/`Pp` (`ui/DateValue`,
`getDateTimeDisplayValue`); never `toLocaleDateString`/`Intl`, which follow the OS locale. Wire/payload
stays `yyyy-MM-dd` and `HH:mm`. Confirm a display change did not alter the request body.

**Testing a date-boundary rule.** Every vitest script pins `TZ=UTC` (`apps/web/package.json`), and
under UTC the correct and the broken implementation agree — so a boundary assertion written there is a
**tautology that cannot fail**. Copy `apps/web/src/utils/date.tz.test.ts`: pin `America/New_York`
(UTC-5, where it manifests) and `Europe/Athens` (UTC+2) per block, and restore `process.env.TZ` in
`afterAll` so it cannot leak into other files sharing the worker.

**Before adding a date predicate, grep for an existing one.** "Overdue" ended up with five
implementations across backend, DB and frontend in two different frames (instant vs calendar day).
Reuse or centralise rather than adding a sixth.
