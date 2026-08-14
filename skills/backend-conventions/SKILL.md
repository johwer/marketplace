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

### Security — four rules that get flagged in review

These are recurring backend security defects, not style preferences. They are **not** in any repo doc: NOVA-3219 attempted to add them to `docs/CODING_STYLE_BACKEND.md` and the additions were removed (always-loaded context files shouldn't carry this specificity). Re-homing to a repo-resident on-demand skill is tracked in **NOVA-3433**. Until that lands, this is the written home — so apply them before opening a PR rather than discovering them in review.

**1. HTML-encode user-controlled values before email-template substitution.**
Values like Department or tag names must pass through `HtmlEncode()` before substitution into an email template, or you have HTML injection.

**2. Company-scoped actions must use `CompanyPermission`, not `UserPermission`.**
`RoleCreate` / `RoleDelete` / `RoleAssign` act on company-owned resources. Gating them with a `UserPermission` is a **privilege-escalation hole** — a user who may edit themselves must not thereby be able to create roles. Match the permission scope to the resource's ownership.

**3. Validate tenancy before acting, and trust the envelope over the payload.**
Always confirm the supplied `companyIds` belong to the given `customerId` before acting on them. In event/message handlers derive the company from `message.CompanyId` (the trusted envelope), **never** from a caller-supplied field like `roleData.CompanyId` — the payload is attacker-influenced, the envelope is not.

**4. Never use EF Core `SetValues()` for upserts on entities with immutable fields.**
`SetValues()` overwrites every mapped column, including immutable ones such as `UserId` and `InsertedAt`. Use an explicit conditional create/update that leaves immutable fields untouched. This one is mechanically detectable — an analyzer or CI grep would beat any written rule, see NOVA-3433.

Related: frontend permission gates are **UX only**; the backend enforces every action independently (already documented in `docs/FRONTEND_COMPONENTS.md`). Never treat a hidden control as an authorization boundary. For which registration layer a new action or permission belongs to, see the note in `/ghost-review` and NOVA-3172's comments — `CompanyAction` wiring lives in `DefaultPermissionsMappings.cs` + `TTPermissionsMappings.cs`, while `ProductMap.cs` + `ServicePermissionMap.cs` govern which *permissions* a product tier may assign.
