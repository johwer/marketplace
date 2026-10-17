# Levels and checklist

The restaurant picture, as an intro: dining room = React app; waiter = API and controller; kitchen = service; pantry = Postgres; the bouncer at the door = middleware and the ServiceC check. Workers and event handlers are the delivery entrance at the back: they skip the waiter.

Each item: id · what you can do · anchor (verify before quoting).

## L1 Apprentice — the request

| Id | Can do | Anchor |
|---|---|---|
| L1.1 | Trace one call: route → controller → service → repository → DB, and back | `services/ServiceA/ServiceA.API/Controllers/ServiceAReportController.cs`, `lift-the-gaze/references/layers.md` |
| L1.2 | Explain why the API returns a DTO and not the entity (contract, data leaks, over-posting) | `layers.md#why-dtos`, `CODING_STYLE_BACKEND.md:480` (no AutoMapper) |
| L1.3 | Say where authorization happens and who decides it (the service asks ServiceC over HTTP) | `ServiceAReportController.cs:70` `CanDoActionOnUser`, `docs/SERVICE_ARCHITECTURE.md` |
| L1.4 | Read the `ApiResponse<T>` envelope and pick the right status (400 vs 403 vs 404 vs 409) | `shared/Repo.Shared.Models/ApiResponse.cs`, owl [RESPONSE-CONTRACT], ghost [BAD-INPUT-IS-4XX] |
| L1.5 | Explain what middleware/attributes do before the action runs (`[Authorize]`, `[AcceptTokens]`) | any controller deriving `RepoController` |
| L1.6 | Regenerate frontend types after a backend change and say why | `/generate-api`, `apps/web/src/api/` |

## L2 Journeyman — the data

| Id | Can do | Anchor |
|---|---|---|
| L2.1 | Spot an EF read that needs `AsNoTracking` or a projection | `dotnet-backend-review` §1 |
| L2.2 | Spot an N+1 (a repository or ServiceC call in a loop) and batch it | ghost [BATCH-DB] |
| L2.3 | Add a migration the right way (generated, never handwritten) and seed data | `feedback_ef_migrations_never_handwrite`, `backend-conventions` |
| L2.4 | Publish an event after the commit, never before | `services/ServiceC/ServiceC.API/Services/CompanyService.cs:164`, owl [PUBLISH-AFTER-COMMIT] |
| L2.5 | Make a handler idempotent (full-row event, upsert by `UpdatedAt`) | `services/ServiceA/ServiceA.Domain/Repository/UserRepository.cs:177` `IsNewerThan` |
| L2.6 | Pick the test level: unit for branching, one happy-path integration test per endpoint | ghost [INTEGRATION-TEST-SPARSITY], owl [INMEMORY-BLINDSPOT] |
| L2.7 | Filter soft-deleted rows (`DeletedAt`) in a new query | `dotnet-backend-review` §1 |

## L3 Senior — the decision

| Id | Can do | Anchor |
|---|---|---|
| L3.1 | Place a gate on the altitude ladder (contract vs retailer vs flag vs ServiceC) and say what disappears below | `lift-the-gaze` Step 1, ghost [CONTRACT-IS-THE-SWITCH] |
| L3.2 | Explain replicas via events and why a service never reads another service's DB | `ServiceA.API/Handlers/UserEventHandler.cs`, ghost [CROSS-SERVICE] |
| L3.3 | Prevent a race: unique index, `UpdatedAt` concurrency token, advisory lock | `UserRepository.cs:154` `pg_advisory_xact_lock`, owl [CONCURRENCY-SCOPE] |
| L3.4 | Change a schema while old pods still run (expand, then contract) | ghost [EXPAND-CONTRACT] |
| L3.5 | Keep the SignedIn migration tooling in step with a schema change | ghost [MIGRATOR-PARITY] |
| L3.6 | Say when a worker/job runs twice with several pods, and what guards it | `dotnet-backend-review` §6 |
| L3.7 | Choose existing mechanism over new one, and name the existing one | ghost [NECESSITY], 2026-10-16 |

## L4 Architect — the system

| Id | Can do | Anchor |
|---|---|---|
| L4.1 | Classify a problem with the four lenses before choosing a fix | `lift-the-gaze` Step 0.5 |
| L4.2 | Measure in Elastic (p95 per endpoint, spans of one trace) before redesigning | `lift-the-gaze` "Measure, don't guess" |
| L4.3 | Explain one Repo vs textbook difference and why we chose it | `dotnet-architecture-reference/repo-vs-textbook.md` |
| L4.4 | Find the standing decision that answers a design question, with date and source | `ghost-review` / `owl-review` / `backend-decisions` |
| L4.5 | Write a yes/no question for the tech lead that only they can answer | `stakeholder-questions` |
| L4.6 | Name the failure mode of a cross-service call (ServiceC down, slow, retried) | `repo-vs-textbook.md` "Sync calls to ServiceC", "HTTP resilience" |
