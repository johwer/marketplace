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

### Visual Verification
- Always take a screenshot in `__screenshots__/` next to the component before pushing.
- Verbal "verified" is not enough — the screenshot is the proof.
