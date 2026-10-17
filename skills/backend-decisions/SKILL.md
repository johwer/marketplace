---
name: backend-decisions
description: Repo backend decisions made by the team, the CTO or other developers (not the tech leads, whose decisions live in ghost-review and owl-review). Dated, sourced by channel, era-tagged (Nova / Polaris / legacy). Load from lift-the-gaze, dotnet-backend-review or a review when checking "was this decided", or when a rule's origin is asked.
user_invocable: true
---

# Backend decisions (team, CTO, other developers)

Decisions about the Repo backend that were not made by a tech lead. The current tech lead's decisions are in `~/.claude/commands/ghost-review.md` (Mode 2 "Standing decisions"). The former tech lead's are in `~/.claude/commands/owl-review.md` (fixed record, he left 2026-08). People are named by role only.

## Precedence

1. The current tech lead (ghost-review) wins over everything below.
2. These decisions come next.
3. The former tech lead (owl-review) stays valid, but loses where it conflicts with a newer decision here or in ghost-review.
4. Repo docs (`docs/`, CLAUDE.md, AGENTS.md).
5. Textbooks (`dotnet-architecture-reference`).

At the same level, a newer decision beats an older one.

## Eras

- **legacy**: SignedIn and the pre-monorepo per-repo services (Repo.ServiceAFollowUp, Repo.ServiceE, ServiceD, the facades). Anything in #backend before 2025-06-28 is about this code.
- **Nova**: the monorepo (`~/Documents/Repo`), first commit 2025-06-28. The #project-nova channel exists since 2024-06-11, as planning.
- **Polaris**: not a separate codebase. It is the Nordic-hosted sovereign cloud, with a dedicated instance for TT, running the Nova architecture (#polaris channel description, 2025-07-30). A Polaris decision is a Nova decision about the TT instance or its hosting.

"Applies to Nova" was checked by grep in the monorepo where the decision is about code. File:line is given where it was checked.

## Layers & API

- 2025-01-28 #backend (backend dev, legacy): new endpoints follow the endpoint standard posted in #style-guide-backend (2024-12-19), and reviewers check it. → applies to Nova: partly. Nova route and DTO rules now come from the current tech lead (ghost [ROUTES], [DTO-NAMING]) and the former tech lead's response standard (owl [RESPONSE-CONTRACT]).
- 2025-03-20 #backend (team: backend devs agreed, frontend dev raised the RTK cost, legacy): every project includes v1 from the start, and each API version gets its own Swagger document, because one doc cannot show which versions an endpoint has. → applies to Nova: yes. `shared/Repo.Shared.Common/Extensions/ApiVersioningExtensions.cs:11-20` defaults to v1, `SwaggerExtensions.cs:43` makes one doc per version, wired in `WebApiExtensions.cs:64`.
- 2025-05-15 #backend (frontend dev asked, former tech lead shipped, legacy): read endpoints that were built as POST get a v2 GET. → applies to Nova: partly. ghost [SEARCH-IS-GET] covers it for new code.
- 2026-04-29 #backend (backend dev, Nova/Polaris): the TT partner endpoint is an upsert and follows the manifest pattern, idempotency included. → applies to Nova: yes, likely `services/ServiceA/ServiceA.Sync.API/Controllers/ServiceAImportController.cs:37` (Idempotency-Key header). Not confirmed that this is the endpoint meant.

## EF & data

- 2023-10-20 #backend (backend dev, legacy): add `.AsSplitQuery()` to queries with many `Include`s, to avoid the cartesian explosion. → applies to Nova: yes. 15 files use it, e.g. `services/ServiceA/ServiceA.Domain/Repository/ServiceAReportRepository.cs:77`.
- 2024-05-17 #backend (backend dev, legacy): Npgsql and the EF Core packages stay on the same major version, or the service fails at runtime (a worker went into CrashLoopBackOff). → applies to Nova: yes. Npgsql.EntityFrameworkCore.PostgreSQL 10.0.2 and Microsoft.EntityFrameworkCore 10.0.9 in the csproj files.
- 2024-09-10 #backend (backend dev, legacy, a tip): when you rename an entity class, keep the table name (`[Table("old_name")]`) so the migration is a rename and not a drop + create. → applies to Nova: partly. A rename still needs expand/contract (ghost [EXPAND-CONTRACT], 2026-10-13).
- 2024-11-07 #backend (backend dev, legacy ServiceB): a new or changed writable PDF template is added as a new `template_form_document` row. Never overwrite the PDF in S3, because documents already created point at the old file. → applies to Nova: partly. Nova ServiceB has the same entity, `services/ServiceB/HealthCaseManagement.Domain/Models/TemplateFormDocument.cs:7`; the rule is not written down for Nova.

## Messaging

- 2024-06-11 #backend (backend dev, legacy ServiceD): ServiceD never resends. On failure it tries the next provider for the channel, and if none is left it gives up. → applies to Nova: yes. `services/ServiceD/ServiceD.API/Providers/ProviderFactory.cs:46` and `:91` ("Will try next provider if available").
- 2025-08-02 #backend (backend dev, legacy): bus handlers run without the user's HttpContext, so they cannot call user-secured APIs. Put the data the handler needs into the message when it is created. → applies to Nova: partly. Nova covers it with full-row-state messages (owl [EVENT-PAYLOAD]) and service tokens on `*.Sync` endpoints (ghost [S2S-VS-USER-API]).

## Config & infra

- 2025-05-06 #backend (backend dev, legacy): one Redis per environment, shared by the services that need it. → applies to Nova: partly. Services read one `REDIS_HOST` per environment (ElastiCache Serverless), e.g. `infra/k8s/service-e/02-configmap.yaml:19` and `infra/k8s/service-a-callback-engine-worker/03-configmap.yaml:22`.
- 2025-08-29 #backend (infra engineer, legacy k8s services): every k8s service must have CORS configured. Fixing it in ServiceC alone is not enough. → applies to Nova: yes, centrally. `shared/Repo.Shared.Common/Extensions/WebApiExtensions.cs:80-86` defines the policies, and `WebApplicationExtensions.cs:94-100` uses AllowAll only in Development.
- 2026-09-30 #backend (backend dev, Nova): the PostHog .NET client does not get the `host` person property the browser sets. The backend sets its own person property (`environment`) and passes it when evaluating flags. APIs read `ASPNETCORE_ENVIRONMENT`, workers `DOTNET_ENVIRONMENT`. → applies to Nova: yes. `services/ServiceD/ServiceD.API/Services/PostHogFeatureFlagService.cs:11-15`, `shared/Repo.Shared.Common/Extensions/OpenTelemetryExtensions.cs:64-65`.
- 2026-06-29 #backend (data analyst raised it, current tech lead replied it is a frontend setting, legacy SignedIn): PostHog must not collect direct identifiers (free text, names, identity numbers, tokens in URLs). Fix it at collection, not by cleaning in the warehouse. → applies to Nova: yes, already done. `apps/web/src/index.tsx:32` (`mask_all_text`) and `:45` (`before_send: sanitizePostHogUrls`).
- 2026-10-13 #backend (data analyst and data engineer, Nova/Polaris): dbt full refresh for Nova and Polaris runs from GitHub Actions, not Airflow, and runs daily. → applies to Nova: yes. `.github/workflows/dbt-full-refresh.yml`.

## Process & release

- 2024-04-08 #backend (CTO, legacy): never retrigger the production error queue unless it is planned and announced, because old notifications reach customers. → applies to Nova: yes. It agrees with ghost 2026-10-06 "plug the hole instead of just continue scooping out the water" and the platform-admin replay endpoint (owl, 2025-09-03).
- 2024-09-30 #backend (CTO, legacy): moving employees from company to company always follows the documented procedure in Confluence, or the replicas (e.g. ServiceE) drift. → applies to Nova: no. It is the SignedIn procedure; Nova has no equivalent written down.
- 2025-06-26 #backend (backend dev, legacy): when you release, deploy to prod. Don't leave master undeployed. → applies to Nova: yes, by pipeline. Every merge to main goes to accept and prod (ghost 2026-02-23).
- 2026-06-02 #backend (data analyst, legacy): the ServiceB→ServiceE event handlers were unreliable and were replaced by an Airflow job. → applies to Nova: no. Nova ServiceE still consumes ServiceB events, `services/ServiceE/ServiceE.API/Handlers/HealthCaseEventHandler.cs`.

## Testing

- No team decision found in #backend. Testing rules come from the tech leads: ghost [MISSING-TEST] (2025-11-24, 2026-01-20) and owl [SEED-SAFETY] (2025-09-19).
