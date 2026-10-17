# Repo backend vs the Microsoft .NET architecture eBooks

Checked against `main` @ `6d94fcd7b` on 2026-10-17. Book refs: **web-apps** = *Architecting Modern Web Applications* (PDF pages); **microservices** = *.NET Microservices* (printed pages). Both are digested in `sources/`.

| Topic | Textbook | Repo | Status |
|---|---|---|---|
| Layers / skipping | Never skip a layer | Controller may call repo | drift |
| Sync calls to ServiceC | No sync calls, not even queries | HTTP to ServiceC on every authz | deliberate |
| Request/reply over bus | Commands and replies are allowed | Forbidden, but one API messages its own worker | drift |
| Shared event library | Don't share one | One shared library, 43 files | partly |
| Outbox | Use an outbox for atomic publish | Save-then-publish, one outbox | partly |
| Gateway / BFF | Gateway per client type | Ingress only, no BFF | deliberate |
| ApiResponse in services | Result type, mapped in one place | Services return `ApiResponse` | deliberate (skill fixed) |
| HTTP resilience | Retry, breaker, timeout | None on any client | undecided |
| Testing levels | Pyramid | Sparse integration tests, doc says otherwise | drift |
| Feature switches | (not covered) | The contract is the switch, leftover PostHog | partly |

**How to read this.** A standing decision beats the textbook. Where they differ, the entry explains the trade-off the team made and points to where it was decided. It does not propose changes. "Drift" means code or a doc disagrees with a newer decision. "Undecided" means no decision was found, which is different from deciding against the book. Sources: the ghost-review and owl-review Standing decisions and tags, the repo docs, the code on `main`, and a walk of #backend from 2023-10 to 2026-10. Three stretches of that walk were only partly read: 2025-06, 2026-06 and 2026-09/10. People are named by role only.

---

### Layers / skipping layers
- **Textbook:** in N-layer, the UI talks only to the business layer and only the business layer talks to data access (web-apps p. 29). DDD services have thin application layers over the domain (microservices p. 196-198).
- **Repo does:** controllers inject repositories directly when there is nothing for a service to add. Example: `services/ServiceA/ServiceA.API/Controllers/CountController.cs:17-18`.
- **Decided where:**
  - Slack #project-nova 2025-10-08, team agreement: "no law that you have to add a abstraction layer that makes no point" ([REPO-PATTERN]).
  - Slack #backend 2024-08-23: someone asked for a rule of thumb between controller→repo and writes routed through a worker. It was settled by the 2025-08-18 rule.
  - Style guide `docs/CODING_STYLE_BACKEND.md:23`: "Do not skip layers (e.g., calling a repository directly from a controller)." This line came in with PR #1438 (PROJ-1497) on 2026-02-09.
- **Why (as stated):** an empty pass-through service is an abstraction that adds nothing. A service exists only when it does work.
- **Status:** drift. `CODING_STYLE_BACKEND.md:23` contradicts the 2025-10-08 agreement. The line was written later, but it was an AI-setup docs PR and nothing records a reversal.
- **Worth asking the tech lead:** Should `CODING_STYLE_BACKEND.md:23` be changed to the 2025-10-08 rule ("controller→repository is fine when a service adds nothing")? Yes/no.

### Core vs infrastructure in *.Domain
- **Textbook:** the Application Core has no infrastructure dependencies. Infrastructure holds the DbContext, migrations and repositories (web-apps p. 32-38, 59-60).
- **Repo does:** `*.Domain` contains EF Core, Npgsql and Dapper, plus the DbContext, the migrations and the repositories. See `services/ServiceA/ServiceA.Domain/ServiceA.Domain.csproj:9-13` and `services/ServiceA/ServiceA.Domain/Repository/ServiceADbContext.cs:15`.
- **Decided where:** no recorded decision found. The skill's digest calls it an "accepted trade-off" (one project shared by the API and the workers) but cites no source.
- **Why (as stated):** not stated. The inferred reason is that API, Sync and Worker projects share one Domain.
- **Status:** undecided.
- **Worth asking the tech lead:** Is "Domain = core + EF persistence in one project" the intended shape? Or A/B: (A) keep it as is, (B) split out an Infrastructure project.

### Repository per entity vs per aggregate, and the specification pattern
- **Textbook:**
  - One repository per aggregate root, and it is the only update path (microservices p. 239-241).
  - Repositories are optional for CRUD services (p. 247).
  - Specification objects bundle filters and includes (web-apps p. 81; microservices p. 253-254).
- **Repo does:** concrete repositories, one per table, with a named method per query. `services/ServiceA/ServiceA.Domain/Repository/` has about 35 of them (`CompanyRepository.cs`, `UserRepository.cs`, …). No specification classes exist in `services/` or `shared/`.
- **Decided where:** no recorded decision found. Related: "backend, follow what we have" (2026-10-06, [REUSE-FIRST]).
- **Why (as stated):** not stated.
- **Status:** undecided.
- **Worth asking the tech lead:** Do repositories stay per table with named query methods, with no specification pattern? Yes/no.

### Unit of work (SaveChanges inside repositories)
- **Textbook:** the DbContext is the unit of work. The application layer (the handler) commits once per operation, through the repository's UnitOfWork (microservices p. 241, 248, 275-277).
- **Repo does:** `SaveChangesAsync` is called 240 times inside `*.Domain/Repository/*.cs`. One example is `services/ServiceA/ServiceA.Domain/Repository/ServiceAExportTransactionRepository.cs`.
- **Decided where:** ghost-review [UNIT-OF-WORK], mined from PRs: "Repositories must not commit… ideally call it once for the entire update." Owl-review [VALIDATE-BEFORE-COMMIT]: #2954 (PROJ-3059) and #3218 (PROJ-3128), where an operation was split over several commits.
- **Why (as stated):** several saves in one operation break atomicity.
- **Status:** drift. The code predates the rule and still contradicts it.
- **Worth asking the tech lead:** Does the no-commit-in-repositories rule apply only to new code, leaving existing repositories alone? Yes/no.

### Table-shaped entities vs rich aggregates
- **Textbook:** behaviour lives on entities and aggregate roots guard invariants (microservices p. 199-209). An anemic model is fine for CRUD but is a smell once rules pile up in services (p. 200-201; web-apps p. 74-76).
- **Repo does:**
  - Entities are table shapes with public setters, for example `services/ServiceA/ServiceA.Domain/Models/Company.cs:10`.
  - Rules go into pure policy classes, for example `services/ServiceA/ServiceA.Domain/Policies/ServiceAOccasionPolicy.cs:6`.
- **Decided where:**
  - Slack #project-new-service-e 2025-05-19: model a state by whether the row exists ([EF-MODELING]).
  - ghost [ONE-HOME-FOR-A-RULE] (2025-11-10, 2026-06-04): one place per rule.
  - No decision on aggregates as such.
- **Why (as stated):** one home per rule, and the entity matches the DB shape.
- **Status:** partly. Where rules go is decided. Whether to use aggregates is not.
- **Worth asking the tech lead:** Are pure `Policies/` classes the agreed home for domain rules, rather than entity methods? Yes/no.

### Sync calls to ServiceC for authorization vs no sync between services
- **Textbook:** "If possible, never depend on synchronous communication… not even for queries". Replicate the data you need instead (microservices p. 50-51, 55).
- **Repo does:** every authorization decision is an HTTP call to ServiceC that returns a bool. See `shared/Repo.Shared.Common/Authorization/AuthorizationAdapter.cs:25` and `:133`.
- **Decided where:**
  - Slack #project-nova 2025-08-11: services ask ServiceC "and get a boolean" ([AUTHZ-OWNER]).
  - Slack #project-kry-advisory-integration 2024-12-06: no permission copy kept via the bus, "we really want to move away from" that.
  - Slack #project-nova 2025-08-18: "The thing we wont do is to use it for any authorization."
  - `docs/SERVICE_ARCHITECTURE.md:5`: "resolves authorization by asking ServiceC over HTTP, rather than resolving permissions locally."
- **Why (as stated):** permission data has one owner. A replicated permission goes stale and is an authorization risk.
- **Status:** deliberate.
- **Worth asking the tech lead:** —

### Authorization in ServiceC vs in-process policies
- **Textbook:** named policies with requirements and handlers, decided inside each service (web-apps p. 71; microservices p. 327-330).
- **Repo does:**
  - Code gates on an Action and ServiceC's ActionMap decides which permission grants it.
  - In-process policies exist only for service authentication (mTLS clients), as in `services/ServiceC/ServiceC.Service.API/Controllers/EligibleResponsibleManagersController.cs:29`.
- **Decided where:**
  - DM 2026-01-19: code gates on the Action, and the ActionMap decides the permission ([PERMISSION-PLACEMENT]).
  - Slack #project-nova 2025-11-10: don't copy ServiceC's action table, add an ServiceC endpoint instead.
  - Slack 2026-06-11: internal ServiceC API + mTLS.
- **Why (as stated):** services hold no "who may do what" logic.
- **Status:** deliberate.
- **Worth asking the tech lead:** —

### Request/reply and commands over the bus
- **Textbook:** single-receiver commands and reply messages are legitimate. Async commands need a failure path. Never fire-and-forget (microservices p. 54-56, 280-281).
- **Repo does:**
  - Nothing uses `bus.Send`. Everything is pub/sub.
  - Exception: the manual FK send API publishes `ManualSocialInsuranceSendRequested` to its own worker and returns "Manual send accepted". See `services/ServiceA/ServiceA.API/Services/SocialInsuranceReportService.cs:26-43`.
- **Decided where:**
  - Slack #backend 2025-08-18: "That we won't do any more no… one of the biggest painpoints" (writes routed through a worker).
  - Slack #project-nova 2025-08-18: "Just not emulate a request over a event bus... There is REST for that."
  - Slack #project_oneentry 2025-11-24: "a 200 OK will not mean processing is finished".
  - PR #3781 (PROJ-4126): the review settled command-vs-event as an event (renamed to past tense). It did not discuss the API-to-own-worker rule.
- **Why (as stated):** async request/reply is error-prone, and a 200 that means "queued" misleads the caller.
- **Status:** drift. The PROJ-4126 code (2026-10-02) contradicts the 2025-08-18 and 2025-11-24 rules.
- **Worth asking the tech lead:** Is the manual FK send (API publishes to its own worker, returns "accepted") an agreed exception to the 2025-08-18 rule? Yes/no.

### Shared event library
- **Textbook:** don't share one integration-events library across services, because it couples them like a shared domain model. Share only bus infrastructure (microservices p. 135).
- **Repo does:**
  - All events live in `shared/Repo.Shared.Messaging/Messages/` (43 files) and inherit `BaseEvent.cs:3`.
  - `EventType` on the base event is a `string` (`BaseEvent.cs:7`), while handlers switch on `Action` enums.
- **Decided where:**
  - Slack #backend 2025-02-03: "in the future it would be good to have a shared message for all services". This was said after local message copies broke a worker and left 9,000+ messages stuck.
  - owl [EVENT-PAYLOAD]: a 2024-03 shape change in the storage service broke ServiceD, and deploys were frozen.
  - `docs/CODING_STYLE_BACKEND.md:231`: "Shared event/DTO types live in `Repo.Shared.Messaging.Messages`".
- **Why (as stated):** local copies drifted and broke consumers. One typed contract fails at compile time instead.
- **Status:** partly. The 2025-02-03 message is a wish and the doc states a convention, but no decision weighs the book's coupling risk.
- **Worth asking the tech lead:** Is the shared events library a firm decision, so that any shape change counts as a cross-service contract change? Yes/no.

### Outbox vs save-then-publish
- **Textbook:** save-then-publish "does not take atomicity into account". Use an event table in the same transaction, plus a resend worker (microservices p. 142-146).
- **Repo does:**
  - Most writes commit and then publish, for example `services/ServiceC/ServiceC.API/Services/CompanyService.cs:164`.
  - There is one real outbox: `services/ServiceD/ServiceD.API/Services/MessageSentOutboxDispatcher.cs:19`.
- **Decided where:**
  - Style guide `docs/CODING_STYLE_BACKEND.md:291-307`, "Transactional Outbox (When to Consider)": only for critical transitions. It was added in PR #2113 on 2026-03-11.
  - Slack #knowledge-sharing 2026-03-11 (tech lead): inbox/outbox when events cascade across services.
  - owl [PUBLISH-AFTER-COMMIT]: #3199 (PROJ-3342), #3176 (PROJ-3274), #2985 (PROJ-3151). Publish after commit, and at minimum log publish failures.
- **Why (as stated):** for simple CRUD sync, "the next event will correct the state anyway" (`CODING_STYLE_BACKEND.md:304`).
- **Status:** partly. When to use an outbox is decided. A shared outbox mechanism is not.
- **Worth asking the tech lead:** Should the ServiceD outbox be generalised into `Repo.Shared.Messaging` before a second service needs one? Yes/no.

### Idempotency approach
- **Textbook:**
  - Use absolute state rather than deltas, an id per event, and dedup at both transport and handler level (microservices p. 149-151).
  - It warns that an old replay can overwrite newer state.
- **Repo does:**
  - Full-row events, and upsert by `UpdatedAt`: `services/ServiceA/ServiceA.Domain/Repository/UserRepository.cs:177`.
  - `ON CONFLICT … DO NOTHING` keyed on the source timestamp: `services/ServiceA/ServiceA.Domain/Repository/ServiceAExportTransactionRepository.cs:42`.
  - Handler-level only, with no transport dedup.
- **Decided where:**
  - Slack #backend 2025-07-04: async messaging without idempotency is "crazy".
  - Slack #project-nova 2025-08-29: "A message on the bus should represent the whole database row it is affecting".
  - PR #2909 (PROJ-2798): decide from local replicated state, not from `EventType`.
  - Slack #project-nova 2026-09-14: a table as an atomicity check for outbound sends.
- **Why (as stated):** with a timestamp, ordering stops mattering. That fixes the book's own replay caveat.
- **Status:** deliberate.
- **Worth asking the tech lead:** —

### Replicas via events (data sovereignty)
- **Textbook:** each service owns its data. Replicate only the attributes you need, in your own language (microservices p. 27-29, 51).
- **Repo does:**
  - User, company and contract replicas are kept up to date by handlers, for example `services/ServiceA/ServiceA.API/Handlers/UserEventHandler.cs:20`.
  - ServiceB→ServiceE is now an Airflow batch job instead of event handlers.
- **Decided where:**
  - Slack #project-proj-service-b 2025-12-03 (current tech lead, backed by the former one): replicate the fields you need, handle deletions, and re-check read access.
  - Slack #project-nova 2025-12-17: a project reference to another service is "Illegal!".
  - Slack #backend 2026-06-02: ServiceB→ServiceE handlers replaced by an Airflow job.
- **Why (as stated):** autonomy. The 2026-06-02 change was because the handlers were unreliable.
- **Status:** deliberate.
- **Worth asking the tech lead:** —

### API gateway / BFF ruled out
- **Textbook:** use gateways or BFFs split per client type and per area, with aggregators behind them. An Ingress alone hides nothing (microservices p. 40-48, 180-181).
- **Repo does:** an ALB Ingress routes `/api/{service}` straight to each API (`infra/k8s/shared/03-ingress.yaml:37-74`). There is no aggregator.
- **Decided where:** Slack #project-proj-service-b 2025-12-03: "No BFF or client stitching". The owning service enriches responses from its replicas. Owl [EVENT-DRIVEN-BOUNDARY].
- **Why (as stated):** the backend delivers final data points. A replica in the owning service matches the book's materialized-view option (p. 32-33).
- **Status:** deliberate.
- **Worth asking the tech lead:** —

### CQRS / MediatR not used
- **Textbook:** simplified CQRS: commands go through the domain, queries go to SQL with Dapper. A MediatR pipeline handles cross-cutting concerns (microservices p. 184-190, 271-289).
- **Repo does:**
  - There is no MediatR reference anywhere.
  - Heavy reads use Dapper, for example `services/ServiceE/ServiceE.API/Repository/InsightsHubRepository.cs:22`.
  - Writes are synchronous in the owning API.
- **Decided where:**
  - Slack #backend 2025-08-18: the CQRS-via-worker-writes style "we won't do any more".
  - Slack #dream-team 2026-02-24: "heavy SQL is done with Dapper".
  - DM 2026-10-06: "backend, follow what we have." For MediatR itself, no recorded decision was found.
- **Why (as stated):** routing writes through a worker was "one of the biggest painpoints".
- **Status:** partly. CQRS-via-workers is rejected and Dapper reads are agreed. MediatR is covered only by "follow what we have".
- **Worth asking the tech lead:** Does MediatR stay out of the backend? Yes/no.

### AutoMapper not used
- **Textbook:** DTOs at the boundary. The reference app maps by hand and the book never prescribes AutoMapper (web-apps p. 37, 56-57, 63).
- **Repo does:** static `MapFromDomain` / `MapToDto` methods. There is no AutoMapper reference in `services/` or `shared/`.
- **Decided where:**
  - Style guide `docs/CODING_STYLE_BACKEND.md:480`: "Do not use AutoMapper — explicit mapping is preferred for traceability and compile-time safety".
  - Slack #project-nova 2025-10-08: "Never return a domain object from a controller."
- **Why (as stated):** traceability and compile-time safety.
- **Status:** deliberate.
- **Worth asking the tech lead:** —

### Stored procedures banned
- **Textbook:** EF by default. Raw SQL or stored procedures where performance matters (web-apps p. 85-86).
- **Repo does:** none. No `CREATE PROCEDURE` or `CREATE FUNCTION` in `services/` or `shared/`. SQL lives in repositories (Dapper).
- **Decided where:** Slack #backend-pull-requests 2025-09-24: "Better to just inject the sql from the backend directly so they are coupled" ([NO-STORED-PROC]).
- **Why (as stated):** a mismatch between a stored procedure and the backend ("90+" vs "91+" bucket) broke prod.
- **Status:** deliberate.
- **Worth asking the tech lead:** —

### ApiResponse<T> envelope vs a service result type
- **Textbook:** services return a result abstraction, and one place (a filter) turns it into HTTP (web-apps p. 63-65).
- **Repo does:**
  - `ApiResponse<T>` implements `IActionResult` (`shared/Repo.Shared.Models/ApiResponse.cs:10`).
  - 207 service files return `Task<ApiResponse…>`, for example `services/ServiceA/ServiceA.API/Services/SocialInsuranceReportService.cs:20`.
- **Decided where:**
  - Slack #style-guide-backend 2024-11-26: the `{status, result, data?, reason?}` standard (owl [RESPONSE-CONTRACT]).
  - Style guide `CODING_STYLE_BACKEND.md:521`: its example shows a service returning `ApiResponse<List<User>>`.
  - Skill `lift-the-gaze/references/layers.md:40,45`: `ApiResponse` is "Wrong here" in services and repositories.
- **Why (as stated):** one envelope for every client. No reason is given for the layers.md ban.
- **Status:** deliberate. `layers.md` was the outlier and was fixed on 2026-10-17 to match the code and `CODING_STYLE_BACKEND.md:521`.
- **Worth asking the tech lead:** —

### Validation placement
- **Textbook:** field rules on DTOs, invariants in entity methods, and `[ApiController]` auto-400 or a validation pipeline (web-apps p. 55; microservices p. 223-227).
- **Repo does:**
  - Hand-written checks in controllers, for example `services/ServiceA/ServiceA.API/Controllers/DeviantController.cs:100`.
  - DB constraints as a backstop.
  - No FluentValidation package anywhere.
- **Decided where:**
  - Style guide `CODING_STYLE_BACKEND.md:89`: "Validate all DTO inputs at the controller level".
  - `:103`: "For complex validation, use FluentValidation or a dedicated validator class".
  - Slack #project-nova 2025-11-05: the `required` keyword, not `[Required]`.
  - Slack #project-nova 2026-03-05: a DB constraint as well, "so its totally impossible", and still a 400 ([BAD-INPUT-IS-4XX]).
  - Slack #backend 2024-12-03: a cap that is "only a client check… you can bypass it".
- **Why (as stated):** descriptive 400s inside the envelope. A 500 from bad input is a bug.
- **Status:** partly. Placement is decided. The FluentValidation option in the doc has never been used and was never discussed.
- **Worth asking the tech lead:** Should the FluentValidation option be removed from `CODING_STYLE_BACKEND.md:103`? Yes/no.

### HTTP resilience (no Polly)
- **Textbook:** typed `IHttpClientFactory` clients with timeout, retry with jitter, and a circuit breaker (microservices p. 294-310).
- **Repo does:**
  - A bare `AddHttpClient()`, and the ServiceC adapter is built by hand (`services/ServiceA/ServiceA.API/Program.cs:128-136`).
  - No Polly or `Http.Resilience` reference anywhere.
- **Decided where:** no recorded decision found.
  - Slack #knowledge-sharing 2024-06-17: someone shared the built-in .NET 8 resilience library. Nothing followed.
  - Slack #backend 2024-06-11: ServiceD never resends, it fails over to the next provider. That is a different mechanism.
- **Why (as stated):** not stated.
- **Status:** undecided. It matters most because ServiceC sits on every request path (see "Sync calls to ServiceC").
- **Worth asking the tech lead:** Should the ServiceC `AuthorizationAdapter` client get the standard resilience handler (timeout + retry + breaker)? Yes/no.

### Caching placement
- **Textbook:** caching goes in its own decorator around the *service*, not in data access. Short TTL or evict on update, and measure first (web-apps p. 89-92).
- **Repo does:**
  - A Redis `IDistributedCache` decorator on the *repository* with a 5-minute TTL (`services/ServiceC/ServiceC.API/Repository/Authorization/CachedAuthorizationRepository.cs:15-25`), plus `CacheInvalidationProcessor`.
  - ServiceE caches report results in Redis.
- **Decided where:**
  - Slack #backend 2024-02-06: "we want… a joint decision" on caching. None was found.
  - Slack #backend 2025-02-05: the org tree is cached for everyone, filtered per user, 1 h TTL.
  - Slack #backend 2025-05-06: one Redis per environment, shared by services.
  - Slack #project-nova 2026-02-17: caches over grants must invalidate on change ([CACHE-INVALIDATION]).
- **Why (as stated):** grants and revokes must take effect at once.
- **Status:** partly. Invalidation and the infrastructure are decided. Where a cache sits is not.
- **Worth asking the tech lead:** Is a decorator on the repository the standard place for a new cache, or should it go on the service? A/B.

### Feature folders vs layer folders
- **Textbook:** organise by feature or vertical slice, not by file type (web-apps p. 60-62).
- **Repo does:**
  - Layer folders: `services/ServiceA/ServiceA.API/{Controllers,Services,Models,Handlers}`.
  - One feature-shaped folder: `ServiceA.API/DeviantRules/`.
- **Decided where:**
  - `docs/API_CONVENTIONS.md:25`: "Prefer many small controllers over one large controller".
  - DM 2026-10-06: "backend, follow what we have." ([REUSE-FIRST])
- **Why (as stated):** consistency with what exists. Small controllers give part of the benefit of slices.
- **Status:** deliberate.
- **Worth asking the tech lead:** —

### Testing levels (integration-test sparsity)
- **Textbook:** a pyramid: many unit tests, fewer integration tests, functional tests via `WebApplicationFactory` (web-apps p. 95-101). EF InMemory hides constraint bugs (microservices p. 132).
- **Repo does:**
  - 651 unit-test files and 179 integration-test files in `services/`.
  - 70 files use `UseInMemoryDatabase`.
- **Decided where:**
  - PRs #3253 (PROJ-3376), "1-3 for the happy path"; #3134 (PROJ-3297), no tests that Postgres does its job; #3420 (PROJ-3657), one real-Postgres test where LINQ translation is at risk; PROJ-3183 review, "be sparse with integrationtests".
  - Slack #project-nova 2025-11-24: integration tests for new endpoints, plus unit tests for branching.
  - Style guide `docs/TESTING_GUIDELINES_BACKEND.md:10`: "If the behavior depends on infrastructure… write an integration test".
  - The same doc at `:8`, "Business logic through API endpoints", and at `:112-122`, InMemory repository tests.
- **Why (as stated):** integration tests are "quite expensive (time budget-wise)". InMemory cannot see translation or index bugs (owl [INMEMORY-BLINDSPOT]).
- **Status:** drift. `TESTING_GUIDELINES_BACKEND.md:8-10` is staler than the sparsity rule from the PRs.
- **Worth asking the tech lead:** Should `TESTING_GUIDELINES_BACKEND.md:8-10` be rewritten to "one happy-path integration test per endpoint, branching in unit tests"? Yes/no.

### Enumeration classes vs enums
- **Textbook:** enumeration classes are optional. Branching on enums across the code is a smell (microservices p. 221-222).
- **Repo does:**
  - Plain enums (`shared/Repo.Shared.Models/Enums/EventType.cs:3`).
  - Behaviour per type sits in strategy classes (`services/ServiceA/ServiceA.API/DeviantRules/DeviantRuleFactory.cs`).
  - ProductType is being replaced by data.
- **Decided where:**
  - Style guide `CODING_STYLE_BACKEND.md:147`: "Prefer enums over boolean flags".
  - Slack #project-nova 2026-08-24: "the ProductType enum is getting nuked, and replaced with pure data" ([PRODUCT-IS-DATA]).
  - Slack #project-proj-service-b 2026-05-28: a formatted `Code` string is the top integration risk, so make it a typed contract.
  - Slack #backend 2025-02-07: change `JsonStringEnumConverter` on producer and consumer together.
- **Why (as stated):** enums make states exhaustive. Branching on product belongs in data.
- **Status:** deliberate.
- **Worth asking the tech lead:** —

### Service contracts as feature switches (vs feature flags)
- **Textbook:** not covered.
- **Repo does:**
  - Entitlements are checked through `ServiceContractExtensions.ActiveAt` (`shared/Repo.Shared.Models/ServiceContracts/ServiceContractExtensions.cs:16`).
  - A PostHog flag service is registered in ServiceD but no code uses it. It carries "TODO remove after PROJ-3473" (`services/ServiceD/ServiceD.API/Services/PostHogFeatureFlagService.cs:6-10`, `Program.cs:122-123`).
  - `PostHog.AspNetCore` is referenced in two ServiceA workers with no code use.
- **Decided where:**
  - Jira PROJ-3847 / Slack 2026-10-12: "No PostHog flag on the backend gate. The contract is the switch."
  - Slack #frontend 2026-05-29: frontend release flags are the norm.
  - Slack #backend 2026-09-30: the backend PostHog client sets person properties from the environment.
  - PR #3640 (PROJ-3571): no reconciler, because the contract gates at read time.
- **Why (as stated):** a flag next to a contract duplicates the entitlement.
- **Status:** partly. The rule is decided, but leftover backend flag wiring remains.
- **Worth asking the tech lead:** Can the unused ServiceD flag service and the PostHog references in the ServiceA workers be removed (PROJ-3473)? Yes/no.

### Domain events (in-process) not used
- **Textbook:** domain events collected on entities and dispatched at save time. Integration events go after commit (microservices p. 227-238).
- **Repo does:** there are no in-process domain events. Services call the publishers directly after the commit (`services/ServiceC/ServiceC.API/Services/CompanyService.cs:164`).
- **Decided where:** no recorded decision found. [PUBLISH-AFTER-COMMIT] covers only the integration-event half.
- **Why (as stated):** not stated.
- **Status:** undecided.
- **Worth asking the tech lead:** Does the backend stay without in-process domain events, with services publishing directly after commit? Yes/no.

---

## Questions to bring to the tech lead

- Should `CODING_STYLE_BACKEND.md:23` "Do not skip layers" change to the 2025-10-08 rule (controller→repo is fine when a service adds nothing)? Yes/no.

- Should `*.Domain` keep the DbContext, migrations and repositories? (A) yes, as now; (B) split out an Infrastructure project.

- Do repositories stay per table with named methods, with no specification pattern? Yes/no.

- Does "no SaveChanges inside repositories" apply only to new code, leaving the existing repos alone? Yes/no.

- Are pure `Policies/` classes the agreed home for domain rules, rather than entity methods? Yes/no.

- Is the manual FK send (an API that publishes to its own worker and returns "accepted", PROJ-4126) an agreed exception to the 2025-08-18 rule? Yes/no.

- Is the shared events library a firm decision, so that every event shape change counts as a cross-service contract change? Yes/no.

- Should the ServiceD outbox move into `Repo.Shared.Messaging` before a second service needs one? Yes/no.

- Does MediatR stay out of the backend? Yes/no.

- Should the FluentValidation option be removed from `CODING_STYLE_BACKEND.md:103`, since nothing uses it? Yes/no.

- Should the ServiceC `AuthorizationAdapter` HttpClient get the standard resilience handler (timeout, retry, breaker)? Yes/no.

- Where does a new cache go? (A) a decorator on the repository, like ServiceC today; (B) a decorator on the service.

- Should `TESTING_GUIDELINES_BACKEND.md:8-10` become "one happy-path integration test per endpoint, branching in unit tests"? Yes/no.

- Can the unused ServiceD PostHog flag service and the PostHog references in the ServiceA workers be removed (PROJ-3473)? Yes/no.

- Does the backend stay without in-process domain events, with services publishing directly after commit? Yes/no.

- Workers with Quartz jobs: (A) they stay at `replicas: 1` on purpose, as an exception to the "at least 2 replicas" rule (2025-04-07); (B) they go to 2+ replicas, and every job gets a distributed lock or a claim row first.
  - Quartz uses the in-memory store with no clustering (no `UsePersistentStore` in `services/` or `shared/`), so every pod runs every job.
  - 19 `IJob`s across five ServiceA and ServiceC workers, 3 with `[DisallowConcurrentExecution]`, none taking a lock in the job itself.
  - The worker deployments checked (deviant engine, callback engine, export, quarantine) run `replicas: 1` (e.g. `infra/k8s/service-a-deviant-engine-worker/03-deployment.yaml`).
  - The engines lock inside their services (`PostgresDistributedLockService`), so some work is already guarded.

## New decisions found in #backend

Sorted 2026-10-17: tech-lead items go to ghost-review / owl-review, the rest are in `~/.claude/skills/backend-decisions/SKILL.md` (with era and Nova relevance). The list below is the raw intake.

Not yet in the ghost-review or owl-review Standing decisions. They are listed here so they can be merged later. Those files were not edited.

- 2023-10-20 #backend: use `AsSplitQuery` for queries with many `Include`s.
- 2024-02-09 #backend: a backend task that needs frontend testing is tested and documented by the backend dev. If it must ship as a package, set it to Blocked.
- 2024-03-04 #backend: `const` for compile-time constants, `readonly` for runtime values.
- 2024-04-08 #backend: don't retrigger the prod error queue unless it is planned and announced.
- 2024-05-17 #backend: Npgsql and EF Core packages share one major version.
- 2024-06-11 #backend: ServiceD never resends. It fails over to the next provider for the channel.
- 2024-09-10 #backend: on an entity rename, keep the table name so EF emits a rename, not a drop+create.
- 2024-09-30 #backend: company-to-company moves always follow the documented procedure, or replicas drift.
- 2024-11-07 #backend: a new writable PDF template is a new row. Never overwrite it in S3.
- 2024-12-03 #backend: limits such as the parallel-service-a cap are enforced server-side, not only in the client.
- 2025-01-28 #backend: new endpoints follow the endpoint standard in #style-guide-backend.
- 2025-02-03 #backend: wish for one shared message type for all services, after local copies broke a worker.
- 2025-02-05 #backend: the org tree is cached once for everyone and filtered per user afterwards, with a 1 h TTL.
- 2025-02-06 #backend: notifications are suppressed per company with a data toggle (`service-d_companies.allowed`), not a code flag.
- 2025-02-07 #backend: enum-converter changes are coordinated across producer and consumer.
- 2025-03-20 #backend: include V1 from the start in every project (.NET ApiVersioning, one Swagger doc per version).
- 2025-05-06 #backend: one Redis per environment, shared by services.
- 2025-05-15 #backend: read endpoints built as POST get a v2 GET.
- 2025-06-17 #backend: a risk assessment is required before a "get all users on a company" endpoint (MEDH-6400).
- 2025-06-26 #backend: dashboard service-e widgets require the role at company level. Department level is not enough.
- 2025-06-26 #backend: deploy to prod whenever you release. Don't leave master undeployed.
- 2025-08-02 #backend: bake the needed data into the message when it is generated, because handlers have no user context for secured APIs.
- 2025-08-18 #backend: no more CQRS-style writes through a worker. "one of the biggest painpoints".
- 2025-08-29 #backend: CORS is configured on every k8s service.
- 2025-11-11 #backend: user creation always goes through `CreateUserRequest` validation, including migrations.
- 2025-11-14 #backend: URL-encode special characters in the department-tag separator.
- 2026-04-29 #backend: the partner endpoint uses the same upsert + idempotency pattern as the manifest.
- 2026-06-02 #backend: ServiceB→ServiceE event handlers replaced by an Airflow job, because the handlers were unreliable.
- 2026-09-30 #backend: the backend PostHog client sets person properties. APIs read `ASPNETCORE_ENVIRONMENT`, workers `DOTNET_ENVIRONMENT`.
- 2026-10-12 #backend: Slack discussion stays in English.
