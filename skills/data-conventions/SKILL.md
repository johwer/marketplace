---
name: data-conventions
description: Data engineering conventions for the Repo monorepo
---

## Loading Conventions

Project-level conventions are loaded automatically via `.claude/skills/backend-conventions.md` when editing `services/**/*.cs` or `shared/**/*.cs` files. Data engineers follow the same backend patterns.

If project-level skills are not available (e.g., older branch), read these files directly:
- `docs/CODING_STYLE_BACKEND.md`
- `docs/API_CONVENTIONS.md`
- `docs/TESTING_GUIDELINES_BACKEND.md`

## DTF Supplements for Data Work

### EF Core Migrations
- Consolidate corrective migrations into a single clean migration before merging.
- Use `dotnet ef migrations remove` and re-add, never edit migration files by hand.
- Always add a data migration when removing or renaming a persisted enum value.
- No regression tests needed for data-only migrations.

### Query Patterns
- Avoid N+1: never execute queries inside loops. Fetch all data in one query, process in memory.
- Materialize `IEnumerable` with `ToList()` before multiple iteration.
- Use database constraints or upsert (`ON CONFLICT`) instead of check-then-act patterns.
- Pass `CancellationToken` through call chains for long-running operations.

### Seed Data
- When adding new tables or schema changes, always add seed data.
- Check the GitHub bot reminder on PRs — it flags missing seed data.
