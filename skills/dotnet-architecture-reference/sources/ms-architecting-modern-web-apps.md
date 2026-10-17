# Architecting Modern Web Applications with ASP.NET Core and Azure

- **Publisher:** Microsoft Developer Division, .NET and Visual Studio product teams
- **Year / edition:** 2023, edition v8.0 (updated for ASP.NET Core 8.0), 118 PDF pages
- **Author:** Steve Smith ("ardalis")
- **Licence:** Copyright Microsoft, all rights reserved (p. 2). This file is a digest in our own words with page references. No passages, listings or tables are reproduced. Short phrases in quotes are marked with a page.
- **Online:** The same guide is likely published as HTML at learn.microsoft.com/dotnet/architecture/modern-web-apps-azure/. The PDF says the e-book is "also available in a PDF format" (p. 2), which suggests a web edition, but the text never gives that URL.
- **Page numbers:** `p. N` is the PDF page (the `===== PAGE N =====` marker in the extracted text). The page number printed in the book is about 9 lower from chapter 1 onward (PDF p. 20 = printed p. 11).
- **Scope note:** The book is about one **monolithic** web app deployed as a single unit (p. 3). It points to a separate microservices e-book for distributed systems. Repo is microservices, so read its project-level advice as advice for *one Repo service*, not for the whole system.
- **Reference app:** eShopOnWeb (p. 10-11), built on the author's Clean Architecture template (p. 32).

---

## Ch. 1 - Characteristics of modern web apps (p. 10-14)

- ASP.NET Core is modular. An app pulls in only the NuGet packages it needs, so it has a smaller footprint and less attack surface (p. 12).
- Built-in DI lets you code against interfaces and swap implementations, for example with fakes in tests (p. 12).
- TestServer hosts the app in memory, so functional tests run the full pipeline (routing, model binding, filters) without a network. The book says these are most valuable for APIs (p. 12).
- One app can serve MVC views, Razor Pages and web APIs together (p. 13).
- A monolith deploys to one endpoint and fits CI/CD pipelines easily (p. 13).

## Ch. 2 - Traditional web app vs SPA (p. 15-19)

- Choose server-rendered pages when the client side is simple or read-only, when it must work without JavaScript, or when SEO matters (p. 15, 16-17).
- Choose a SPA when the UI is rich, the team knows JS/TS, or there is already an API for other clients (p. 15, 17-18).
- SPAs need more architecture and security skill, and their frameworks change faster (p. 15).
- SPAs suit apps behind a login that search engines cannot reach anyway (p. 19).
- *Repo:* React SPA + REST APIs. This is the SPA case the book describes.

## Ch. 3 - Architectural principles (p. 20-25)

- **Separation of concerns:** keep business behaviour apart from infrastructure and UI. Ideally the business rules sit in their own project that depends on no other project in the solution (p. 20).
- **Encapsulation:** components change their internals freely as long as the public contract holds. The book says an architecture that integrates through a shared central database depends on mutable global state (p. 20-21).
- **Dependency inversion:** compile-time dependencies point toward abstractions. The caller owns the interface and the implementation depends on it. This is what makes DI possible (p. 21-23).
- **Explicit dependencies:** a class asks for everything it needs in its constructor. A class that quietly needs global or infrastructure state is "dishonest with their clients" (p. 23).
- **Single responsibility:** one reason to change. At architecture level: UI in the UI project, data access in infrastructure, rules in the core. Taken all the way, this gives one responsibility per microservice (p. 23-24).
- **DRY:** one authority for each behaviour. But do not merge logic that is only coincidentally the same: duplication is better than coupling to the wrong abstraction (p. 24).
- **Persistence ignorance:** persisted types should not depend on the storage technology. The book lists violations: required base class or interface, Active Record, required parameterless constructor, required `virtual`, persistence attributes (p. 24-25).
- **Bounded contexts:** each context owns its own names and has exclusive access to its own store. Contexts talk through programmatic interfaces, not a shared database. They map closely to microservices (p. 25).

## Ch. 4 - Common web application architectures (p. 26-44)

- **All-in-one:** one project, with folders as the only separation. As it grows, UI pieces spread across folders and nothing says which folder may depend on which, which leads to spaghetti code (p. 26-27).
- **Layers:** they allow reuse, let you limit who may call whom, and let you replace a layer (for example persistence, or a fake for tests) (p. 27-28). Layers are logical. Tiers are physical deployment targets (p. 28).
- **Traditional N-layer (UI -> BLL -> DAL):** the UI talks only to the BLL, and only the BLL talks to the DAL. The flaw: compile-time dependencies run top to bottom, so business logic depends on data access and is hard to test without a database (p. 29).
- **Clean architecture** (also known as hexagonal, ports-and-adapters, onion): the Application Core is at the centre and has no dependencies on other layers. It defines interfaces that Infrastructure implements. UI and Infrastructure both depend on the Core, not on each other (p. 32-34).
- At run time the UI needs the Infrastructure implementations wired in through DI, but at compile time it should only see Core interfaces (p. 34). The Core is easy to unit test. Infrastructure is tested with integration tests (p. 35-36).
- **What goes where** (p. 37-38):
  - *Application Core:* entities, aggregates, interfaces, domain services, specifications, custom exceptions and guard clauses, domain events and handlers. It may also hold simple DTOs.
  - *Infrastructure:* DbContext, migrations, repository implementations, infrastructure services (mail, files).
  - *UI:* controllers, filters, middleware, view models, startup/composition root.
- The UI must not instantiate or statically call Infrastructure types. A UI-to-Infrastructure project reference is tolerated only for DI wiring in the composition root (p. 38).
- **Containers:** a monolith in one container is fine. Splitting into microservices is worth it only if you can deliver feature slices that run independently and need to scale separately. Otherwise it adds overhead: an event bus, retries, eventual consistency (p. 39-41).
- Other styles mentioned: Web-Queue-Worker (front end plus a worker over a queue), N-tier, microservices, each one business capability inside a bounded context (p. 43).

## Ch. 5 - Client-side technologies (p. 45-51), brief

- Keep HTML, CSS and JS separate (separation of concerns). Avoid inline styles (p. 45-46).
- Declarative data binding beats imperative DOM code as behaviour grows (p. 47-48).
- React is a view library only. You choose and combine routing, API and state libraries yourself (p. 49).
- To pick a SPA framework, judge team familiarity, how opinionated it is, documentation, and how active the community and core team are (p. 50-51).

## Ch. 6 - Developing ASP.NET Core MVC apps (p. 52-77)

- **API vs pages:** for web APIs use MVC controllers, starting from the Web API template. Razor Pages are for page UIs (p. 53).
- **Validation:** check model validity before any state change. `[ApiController]` returns 400 automatically for invalid models and requires attribute routing (p. 55).
- **Thin controllers:** big controllers collect dependencies. The book suggests the mediator pattern (one handler per action) or the ApiEndpoints package, so the controller only does routing and binding (p. 55-57).
- **Dependencies:** watch for "static cling" (static calls with side effects) and remember "new is glue" (p. 57-58). Ask for dependencies through constructors. Do not build infrastructure objects inline (p. 59).
- **Project split:** UI, Infrastructure and ApplicationCore as separate libraries. The Core has as few dependencies as possible and *none* on infrastructure. Infrastructure references EF Core and implements Core interfaces. Ideally the UI does not reference Infrastructure at all, for example by using Autofac modules (p. 59-60).
- **Feature folders:** organise by feature instead of by file type (feature or vertical slices), using Areas or your own conventions. For APIs a folder per feature can hold its endpoints and DTOs (p. 60-62).
- **Separate API projects:** secured APIs should ideally be their own project, because their deployment, load and authentication (token, not cookie) differ (p. 62). A shared DTO project should not be the whole business core (p. 63).
- **Cross-cutting concerns:** filters for authorization, validation, "not found" checks and error policy. Action methods should end up "extremely thin" (p. 63-65). A *result abstraction* returned by services and turned into HTTP results in one place is suggested (p. 65).
- **Security:** authentication identifies the caller and authorization limits what they reach (p. 66). APIs use JWT bearer tokens, not cookies or login redirects (p. 69-71). Prefer named policies over role strings scattered across attributes (p. 71). Do not put secrets in JWTs (p. 72). Do not write your own crypto, membership or token system (p. 73). Client-side checks are never enough: authorize on the server (p. 70).
- **DDD - should you?** Use it for large domains with real business complexity. Skip it for CRUD. If your "domain model" has no behaviour (anemic), rethink. A hybrid works: DDD for transactional parts, a simple read model for reports and dashboards (p. 74-76).
- **Deployment:** `dotnet publish`, a process manager, and Kestrel behind a reverse proxy that handles TLS. Containers are increasingly the norm (p. 76-77).

## Ch. 7 - Working with data (p. 78-93)

- Keep the data access choice out of ApplicationCore and UI. Put it in Infrastructure (p. 78).
- **EF Core** is the default for relational data. Inject the DbContext through DI (p. 78-79).
- **Queries:** materialise with `ToListAsync`. Returning `IQueryable` lets callers add operators that fail at run time, so it is safer to pass filters in and return a list (p. 80). Use async in web apps (p. 81).
- **Related data:** use eager `Include`. Avoid explicit and lazy loading in web apps, because they add round trips that only show up in production. Watch for Cartesian explosion (`AsSplitQuery`) (p. 81-82).
- **Specification pattern:** a specification object holds a query's filter *and* its includes, so the repository stays generic (p. 81). See also the DDD patterns list (p. 75).
- **Encapsulated entities:** expose collections as read-only and change them through methods. Map the private backing field in EF. Use owned types for value objects (p. 82-83).
- **Resilience:** EF retry strategies. With explicit transactions, run the whole unit inside the execution strategy (p. 83-84).
- **EF Core vs Dapper:** Dapper is faster but has no compile-time safety and every query must change with the model. EF is good enough for most paths. Use custom SQL where it matters (p. 85-86).
- **SQL vs NoSQL:** relational databases give normalisation and foreign keys. NoSQL gives scale but brings duplication and versioning problems. Mixing both is fine (p. 86-87).
- **Caching:** keep caching out of data access and UI code. Put it in its own class, a decorator around the service, and control it through configuration (p. 89-91). Keep durations short and/or evict on update to limit stale data (p. 91-92). Measure before you cache (p. 92).

## Ch. 8 - Testing (p. 94-104)

- Unit tests run in memory with no file system, network or database (p. 94). Integration tests check how the layers fit together on real infrastructure (p. 95). Functional tests take the user's view (p. 95).
- Testing pyramid: many unit tests, fewer integration tests, fewest functional tests. Each level should only cover what the level below cannot (p. 95-96).
- What to test: conditional branches, the happy path and the sad path, and things that can actually fail. Do not chase coverage for its own sake (p. 96).
- Organise tests by type and by target. A common compromise is one test project per test type per app (p. 97).
- Name tests after the class, method and expected behaviour, never `Test1` (p. 98-99).
- Controllers should be thin enough to need little unit testing. Test them with functional tests on TestServer / `WebApplicationFactory` (p. 100-101).
- Integration tests mostly target Infrastructure, for example that EF reads and writes what you expect (p. 101).

## Ch. 9-10 - Dev process and Azure hosting (p. 105-118), brief

- CI builds and tests on every commit to shared branches and produces a deployable artifact. CD deploys it, usually to staging first (p. 107-109).
- Monitor production with telemetry (p. 109).
- Containers give the same configuration in every environment. An API gateway or BFF decouples clients from many back ends (p. 113-115).
- Use a service bus for non-trivial messaging between apps (p. 117). The rest is Azure product guidance and does not apply to Repo's AWS stack.

---

## Repo mapping

| Book concept | Book's guidance (short) | Repo today (file/doc) | Verdict | Note |
|---|---|---|---|---|
| Clean architecture core | ApplicationCore has no infrastructure dependencies. Infrastructure implements its interfaces (p. 32-34, 59-60) | `*.Domain` references EF Core, Npgsql and Dapper, and holds `Repository/ServiceADbContext.cs` and `Migrations/` (`services/ServiceA/ServiceA.Domain`) | **conflicts** (with the book, not with a team decision) | Repo's Domain is "Core + Infrastructure" in one project. The dependency points *down* to EF, not inward. Accepted trade-off: one project to share between API and workers. |
| N-layer flow | UI -> BLL -> DAL. The UI never calls the DAL (p. 29) | `CODING_STYLE_BACKEND.md` "Do not skip layers" and `lift-the-gaze/references/layers.md` "A controller never calls a repository directly" | **conflicts with a standing decision** | The 2025-10-08 team agreement ([REPO-PATTERN], `ghost-review.md`) allows controller -> repository when a service would add nothing. The two docs are stale against it. |
| Thin controllers / pass-through layers | Move work out of actions (mediator, endpoints, filters) (p. 55-57, 65) | [REPO-PATTERN]: flag a pass-through service, not a direct repo call | **partly** | Both aim at thin controllers. The book adds an indirection (a handler per action). Repo removes an empty indirection instead. Neither uses MediatR. |
| Repository + specification | Generic repository plus a specification object that holds filters and includes (p. 37-38, 81) | Specific repositories with named methods per query (`*.Domain/Repository`). No specification classes found. | **partly** | Repositories stay concrete. layers.md says the caller passes scope (customerId, companyIds) in. A specification only pays off if many queries share filter and include shapes. |
| Return lists, not IQueryable | Pass filters in, return a materialised list (p. 80) | "Materialize IEnumerable before multiple use" (`CODING_STYLE_BACKEND.md`) | fits | Same rule, slightly different wording. |
| Persistence ignorance | No persistence attributes, base classes or `virtual` on entities (p. 24-25) | Entities in `*.Domain/Models` are EF-shaped (audit timestamps, EF naming conventions, JSONB rules) | **partly** | Entities are the database shape by design (layers.md: "Models/ = entities (the database shape)"). We do not aim to swap storage. |
| Rich vs anemic model | DDD wants behaviour on entities. Anemic is a warning sign, but a simple read model for reports is fine (p. 75-76) | Rules live in `*.Domain/Policies` (for example `ServiceAOccasionPolicy`) and services. Entities are mostly data. | **partly** | This is the book's hybrid: rules in pure policies rather than on entities. ServiceE fits the "read model, no aggregates" case. |
| Bounded context, own store | Each context has exclusive access to its own store and talks through interfaces, not a shared database (p. 25) | One Postgres DB per service. ServiceC is asked over HTTP, never through its database (`SERVICE_ARCHITECTURE.md`). A project reference to another service is "Illegal!" (2025-12-17). | fits | Repo is stricter than the book because it is distributed. |
| Explicit dependencies / DI | Constructor injection, avoid static cling and "new is glue" (p. 23, 57-59) | Primary constructors, interface-based Scoped registration (`CODING_STYLE_BACKEND.md` DI section) | fits | "Shared NuGet never fetches its own secrets; the consumer passes them in" (owl-review standing decision) is the same principle. |
| DTOs at the boundary | DTOs for API request/result types. A public API defines its own types (p. 37, 63) | Explicit `MapFromDomain`, **no AutoMapper**, "Never return a domain object from a controller" (2025-10-08) | fits | The book never prescribes AutoMapper. The eShopOnWeb handler maps by hand (p. 56-57). |
| Feature folders | Organise by feature, not by file type (p. 60-62) | Layer folders: `Controllers/`, `Services/`, `Models/`, `Handlers/` in `*.API`. One controller per sub-resource (`API_CONVENTIONS.md`). | **partly** | Small focused controllers give some of the benefit. Moving to slices would break "backend, follow what we have" (2026-10-06), so do not adopt it piecemeal. |
| Result abstraction | Services return a result type and one place turns it into HTTP (p. 65) | `ApiResponse<T>` with a Result enum, built in the controller (`CODING_STYLE_BACKEND.md` Response Model) | **partly** | Repo has the envelope but builds it per action, not through a filter. layers.md forbids `ApiResponse` in services, so a service-level result type would be a new type, not `ApiResponse`. |
| Validation | `[ApiController]` gives automatic 400. Validate before any state change (p. 55) | Explicit `ApiResponse.ValidationError("...")` checks in the controller, plus the `required` keyword (2025-11-05) | **partly** | Same "validate at the edge" rule. Repo writes the checks by hand for descriptive messages inside the envelope instead of ProblemDetails. |
| Authorization policies | Named policies and claims, decided in-process (p. 71) | Services ask ServiceC over HTTP and get a boolean. Code gates on the Action and the ActionMap decides which permission grants it (2026-01-19). | **partly** | Same idea (do not scatter role strings) at a different level. A local policy that reads ServiceC data would break "services contain no who-may-do-what logic" (2025-08-11). |
| API auth | JWT bearer for APIs, never redirects. Do not roll your own security (p. 69-73) | JWT through `AddRepoWebApi`. ServiceC issues tokens, with short lifetimes and rotation (owl-review 2025-04-07). | partly | Repo *does* run its own token service (ServiceC). The book's warning is a reason to keep it small and reviewed. |
| Caching as decorator | Caching in its own class, not in data access or UI. Short TTL or evict on update (p. 89-92) | `ServiceC.API/Repository/Authorization/CachedAuthorizationRepository.cs`, `CacheInvalidationProcessor.cs`. Caches must invalidate on grant and revoke (2026-02-17). | **partly** | It is a decorator (good), but it sits on the repository, which the book advises against (p. 89). Eviction on change matches the book. |
| Lazy loading / N+1 | Avoid lazy and explicit loading. Eager `Include`, watch query counts (p. 81-82) | "Avoid N+1 queries" (`CODING_STYLE_BACKEND.md`). No parallel queries on one DbContext (2025-11-19). | fits | |
| EF vs Dapper / raw SQL | EF by default. Raw SQL or stored procedures where needed (p. 85) | EF Core + Dapper for complex queries. **No stored procedures** (2025-09-24). | partly | The book lists stored procedures as an option. Repo bans them because SQL in the backend stays coupled to the code. |
| Microservices trade-off | Split only for independent slices and scaling. Splitting brings a bus, retries and eventual consistency (p. 40-41) | Rebus/RabbitMQ, idempotent handlers, outbox notes (`CODING_STYLE_BACKEND.md` messaging). ServiceC merged org, user and auth because they called each other most (2025-01-02). | fits | Repo merged services along that line, which is the book's own reasoning. |
| Web-Queue-Worker | Front end plus a worker over a queue (p. 43) | `*.Worker.*` projects alongside `*.API`, sharing `*.Domain` | fits | This is why rules that workers also need live in Domain (layers.md "side doors"). |
| Test pyramid / projects | Many unit tests, fewer integration tests, functional tests via `WebApplicationFactory`. One test project per type per app (p. 95-101) | `.Test` + `.IntegrationTests` per project. `SyncWebApplicationFactory`, Testcontainers in ServiceB worker tests. "Write integration tests for new endpoints" (2025-11-24). | fits / partly | Repo leans more on integration tests for endpoints. Some unit tests use the EF InMemory provider, which the book only suggests for functional tests. |

---

## Questions this source helps answer

- *Should this logic live in the Domain project or the API service?* Ch. 4 "Organizing code" (p. 37-38) for the clean-architecture answer, then the mapping rows "Clean architecture core" and "Web-Queue-Worker". In Repo, if a worker also needs it, it goes in Domain.
- *Do I need a service between this controller and the repository?* N-layer (p. 29) and thin controllers (p. 55-57) against the [REPO-PATTERN] row: only if the service adds something.
- *Should my repository return `IQueryable` or take a specification?* p. 80 (return lists) and p. 81 (specifications). The mapping row explains why Repo keeps named repository methods.
- *Where does caching go, and how do I avoid stale data?* p. 89-92, and the ServiceC `CachedAuthorizationRepository` row.
- *Should entities carry behaviour or should rules go in a policy class?* DDD section (p. 74-76) and Ch. 7 encapsulation (p. 82-83). See the "Rich vs anemic" row.
- *Is it worth splitting this into a new service or worker?* Monolith vs microservices (p. 39-41) and the bounded-context principle (p. 25).
- *How should validation, not-found and error policy avoid repeating in every action?* Filters and result abstraction (p. 63-65). See the "Result abstraction" and "Validation" rows for what Repo does instead.
- *Where should authorization be decided?* Security (p. 66-73) against `SERVICE_ARCHITECTURE.md`: ServiceC decides, the service gates on the Action.
- *Unit, integration or functional test for this?* Test pyramid and "what to test" (p. 95-96, 100-101).
- *Is a direct `new` or static call here a coupling problem?* "Static cling" and "new is glue" (p. 57-58).
