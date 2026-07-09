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
