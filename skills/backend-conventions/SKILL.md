---
name: backend-conventions
description: Backend coding conventions for the Repo monorepo
---

## Loading Conventions

Project-level conventions are loaded automatically via `.claude/skills/backend-conventions.md` when editing `services/**/*.cs` or `shared/**/*.cs` files.

If project-level skills are not available (e.g., older branch), read these files directly:
- `docs/CODING_STYLE_BACKEND.md`
- `docs/API_CONVENTIONS.md`
- `docs/TESTING_GUIDELINES_BACKEND.md`

## DTF Supplements

These patterns come from team experience and are not in the project-level skills:

### JSONB Columns — Critical
- Do NOT add `[JsonPropertyName("snake_case")]` to models stored as JSONB.
- The shared JSONB serializer (`EntityFrameworkExtensions.JsonbSerializerOptions`) uses `JsonNamingPolicy.SnakeCaseLower` automatically.
- Adding explicit attributes causes API/Swagger/RTK mismatch → `undefined` at runtime.

### Seed Data
- When adding new tables or schema changes, always add seed data.
- Check the GitHub bot reminder on PRs — it flags missing seed data.

### Enum Removal Migrations
- Always add a data migration when removing or renaming a persisted enum value.
- Without it, existing rows with the old value will cause deserialization failures.

### Inter-Service Messaging (Rebus + RabbitMQ)
- Events inherit from `BaseEvent`. Shared types in `Repo.Shared.Messaging.Messages`.
- **Handlers MUST be idempotent** — use upserts, not create.
- Re-throw exceptions in handlers for Rebus retry (5 attempts, then error queue).
- Never make synchronous HTTP calls to other services from event handlers.

### API Generation
- After changing backend endpoints, regenerate frontend types: `/generate-api`
- Never run `npx @rtk-query/codegen-openapi` directly — use `npm run generate:api:{service}` from `apps/web/src/api/`.
