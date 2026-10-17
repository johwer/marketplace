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
- 2025-03-18 #project-nova (team, Nova planning): one login credential per type + identifier; the performer's name goes in the JWT and in event logs; only rehab coordinator and customer support act across customers. The part "configuration lives on the company" is superseded by customer templates and customer-level admin roles. → applies to Nova: partly. Only `Username` is unique (`IamDbContext.cs:251`).
- 2026-02-04 #project-proj-subscription-and-roles (PO, Nova): external subscribers belong to no company or customer and have no name. → applies to Nova: yes. `ServiceD…/Domain/ExternalReceiver.cs:5-11`.
- 2026-02-09 #project-proj-subscription-and-roles (backend dev, PO ok, Nova): an external receiver on a role has the same shape as on a user: channel + address. → applies to Nova: yes. `ExternalReceiverRoleAssignmentRequest.cs`.
- 2026-03-03 #project-nova (PO + former tech lead, Nova): the service-a types offered come from the company's templates, never hardcoded per retailer. → applies to Nova: yes (not checked in code).
- 2026-03-10 #project-nova (PO, Nova): confidentiality of the cause is an explicit choice, and only the service-a owner may raise or lower it. → applies to Nova: yes. `ServiceAReportService.cs:292`.
- 2026-04-27 #project-nova (backend devs, Nova): bulk endpoints create companies and login configurations within one customer. → applies to Nova: yes. `CompanyController.cs:94`, `CompanyLoginConfigurationController.cs:149`.

## EF & data

- 2023-10-20 #backend (backend dev, legacy): add `.AsSplitQuery()` to queries with many `Include`s, to avoid the cartesian explosion. → applies to Nova: yes. 15 files use it, e.g. `services/ServiceA/ServiceA.Domain/Repository/ServiceAReportRepository.cs:77`.
- 2024-05-17 #backend (backend dev, legacy): Npgsql and the EF Core packages stay on the same major version, or the service fails at runtime (a worker went into CrashLoopBackOff). → applies to Nova: yes. Npgsql.EntityFrameworkCore.PostgreSQL 10.0.2 and Microsoft.EntityFrameworkCore 10.0.9 in the csproj files.
- 2024-09-10 #backend (backend dev, legacy, a tip): when you rename an entity class, keep the table name (`[Table("old_name")]`) so the migration is a rename and not a drop + create. → applies to Nova: partly. A rename still needs expand/contract (ghost [EXPAND-CONTRACT], 2026-10-13).
- 2024-11-07 #backend (backend dev, legacy ServiceB): a new or changed writable PDF template is added as a new `template_form_document` row. Never overwrite the PDF in S3, because documents already created point at the old file. → applies to Nova: partly. Nova ServiceB has the same entity, `services/ServiceB/HealthCaseManagement.Domain/Models/TemplateFormDocument.cs:7`; the rule is not written down for Nova.
- 2025-08-19 #project-nova (data analyst, Nova): column names use `_at` for times and `is_` for booleans. → applies to Nova: partly. `_at` is followed; `is_` is not (`Activated`, `ServiceAAutomationPaused`).
- 2026-07-10 #project-nova (PO + team, Nova): templates are soft-deleted ("Delete", not "Archive") and never reopened. → applies to Nova: yes. ServiceB `Domain/Models/Template.cs:42,60`.
- 2026-03-16 #project-nova (backend dev, PO confirmed, Nova): the deviant engine looks back 12 months and counts only days inside the window; it never recalculates an active Recurring deviant; deleting an service-a recomputes the deviant; with an active case the new deviant is appended to the reason, without one a recommendation is created. → applies to Nova: not checked.

## Messaging

- 2024-06-11 #backend (backend dev, legacy ServiceD): ServiceD never resends. On failure it tries the next provider for the channel, and if none is left it gives up. → applies to Nova: yes. `services/ServiceD/ServiceD.API/Providers/ProviderFactory.cs:46` and `:91` ("Will try next provider if available").
- 2025-08-02 #backend (backend dev, legacy): bus handlers run without the user's HttpContext, so they cannot call user-secured APIs. Put the data the handler needs into the message when it is created. → applies to Nova: partly. Nova covers it with full-row-state messages (owl [EVENT-PAYLOAD]) and service tokens on `*.Sync` endpoints (ghost [S2S-VS-USER-API]).
- 2026-01-28 #project-proj-subscription-and-roles (backend dev, Nova): subscription claims live in ServiceD, keyed on the ServiceC roleId; ServiceC does not hold them. → applies to Nova: yes. `RoleSubscriptionConfigurationRequest.cs:8`. Note: the same thread has the PO rule that unticking a role's subscriptions clears them for every holder (behind a confirm). That sits in tension with ghost 2026-06-30 (a partial update is not replace-all); check before building it.
- 2026-03-10 #project-proj-subscription-and-roles (PO, Nova): reset-password and MFA emails exist in sv/fi/en and follow the user's language. → applies to Nova: not checked.
- 2026-03-27 #project-nova (backend dev, Nova): notes created by the migration endpoint send no email, but their inbox message is templated. → applies to Nova: not checked.
- 2026-10-05 #project-proj-signedin-migration (backend dev, Nova): migrated customers are muted so nobody gets double notifications. → applies to Nova: yes. ServiceC `CustomerResponse.cs:21` `SuppressNotifications`.

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
- 2026-09-01/25 #project-proj-signedin-migration (PO, Nova): old access rights are first recreated as Nova permissions, then migrated 1:1 to roles. → applies to Nova: yes. `Migrators/Provisioning/AccessRightRoleMap.cs`.
- 2026-09-25/10-12 #project-proj-signedin-migration (PO + team, Nova): AA + EF on the same target becomes only the combined role, which carries historical service-a. → applies to Nova: yes. `AccessRightAssignmentPlanTests.cs:597`.
- 2026-10-05 #project-proj-signedin-migration (backend dev, Nova): identical ServiceB templates fold into one customer template, written as `Custom`, not `Default`. → applies to Nova: yes. `HealthCaseTemplatePlan.cs:80-88`, `HealthCaseTemplateMigrator.cs:24`.
- 2026-10-06 #project-proj-signedin-migration (PO, Nova): manager rights when department and direct managers both exist: only the department manager configured → take its rights; same → common; different → the minimum common set; none → nothing, but keep manual grants. → applies to Nova: not checked.
- 2026-10-06 #project-proj-signedin-migration (PO, Nova): SignedIn shows UTC as local time; Nova does not copy that bug (ticket cancelled). → applies to Nova: yes. Agrees with owl 2025-08-15.
- 2026-10-13/14 #project-proj-signedin-migration + #project-nova (data analyst, Nova): FK cutover switches legacy off per company row (a customer row is not enough); migrated legacy reports are marked sent; no remigration of the customer after cutover. → applies to Nova: not checked.

## Testing

- No team decision found in #backend. Testing rules come from the tech leads: ghost [MISSING-TEST] (2025-11-24, 2026-01-20) and owl [SEED-SAFETY] (2025-09-19).
