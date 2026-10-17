# .NET Microservices: Architecture for Containerized .NET Applications

- **Publisher:** Microsoft Developer Division, .NET and Visual Studio product teams
- **Year / edition:** 2023, edition v7.0 (updated for ASP.NET Core 7.0), 350 PDF pages
- **Licence:** Copyright Microsoft, all rights reserved. This file is a digest in our own words with page references. No passages, listings or tables are reproduced. Short phrases in quotes carry a page number.
- **Online:** The guide is likely also published as HTML at learn.microsoft.com/dotnet/architecture/microservices/. The PDF says the e-book is "also available in a PDF format" (PDF p. 2), which suggests a web edition, but the text never gives that URL.
- **Page numbers:** `p. N` is the **printed** page number (the number in the book's own table of contents). The PDF page (the `===== PAGE N =====` marker in the extracted text) is 15 higher: printed p. 27 = PDF p. 42. The sibling digest `ms-architecting-modern-web-apps.md` uses PDF pages, so don't compare numbers across the two files.
- **Reference app:** eShopOnContainers. The book says it is a showcase in "permanent beta" and not a production template (PDF p. 4). Its own event bus over RabbitMQ is for dev/test only (p. 138, 141).
- **How to read it for Repo:** chapters 3 (architecture), 5 (integration events, idempotency) and 6 (DDD/CQRS) carry the substance. The Docker, Visual Studio and Azure chapters are tooling for 2017-2023 and are only skimmed here. Some details are dated: eShopOnContainers later moved from Ocelot to Envoy (p. 163), and from Polly in code to a Linkerd mesh for HTTP retries (p. 291).

---

## Ch. 3 - Microservice architecture (p. 25-65)

### What a microservice is (p. 25-27)
- A microservice is a small service with its own process. It implements one business capability inside one context boundary, is developed and deployed on its own, and owns its domain model and data (p. 25-26).
- Size is not the point. Aim for loose coupling and high internal cohesion, and keep services small only as long as they don't build many direct dependencies on each other (p. 26).
- The book counts SOA-style central brokers, central orchestrators and an ESB as anti-patterns in the microservice world (p. 25).
- Going to production needs: monitoring and health checks, scalable infrastructure, and security at several levels: authentication, authorization, secrets, secure transport (p. 27).

### Data sovereignty per microservice (p. 27-29)
- Each microservice owns its domain data and logic. The conceptual model differs between services, just as it does between bounded contexts (p. 27-28).
- A single shared database looks simpler but grows huge tables serving many subsystems. The book's analogy is one map for hiking, driving and geography lessons at once (p. 28).
- A service's data is private. Others reach it only through its API (HTTP/gRPC) or through messaging (p. 28-29).
- Consequences: no ACID transaction across services, no cross-database constraints, no distributed transactions. A business process that spans services must use **eventual consistency** (p. 29).
- Polyglot persistence (mixing SQL and NoSQL per service) is allowed (p. 29).

### Bounded contexts and boundaries (p. 29-32, 36-39)
- The microservice idea comes from DDD's bounded context. Each BC has its own model, database and ubiquitous language (p. 29).
- The same identity can appear under different names and shapes in different BCs. The user in the identity service is the Buyer in ordering. Each BC keeps only the attributes it needs (p. 29, 38-39).
- One BC per service is a good starting point, but one BC may be several physical services. The reverse is not allowed: one service must not span several BCs (p. 29-30, 37).
- Finding boundaries: look for decoupled islands of data and for places where the business vocabulary changes (p. 31-32).
- **Don't unify terms across domains.** Accept that each domain names things its own way (p. 37).
- Right-sized boundaries show few strong relationships between models. Typical operations should not need data merged from several models (p. 37).
- Boundary sizing is iterative. If an area needs many dependencies, that cohesion means it belongs in one service (p. 36-37).
- Context mapping makes the boundaries and integration contracts explicit (p. 37).
- Org structure shapes boundaries, and sometimes you deliberately design boundaries for the organisation you want (p. 37).
- Keeping a different user shape per service avoids duplicating data nobody needs. It also gives each data type one owning service that drives all its updates (p. 39).

### Logical vs physical architecture (p. 30-31)
- "Microservice" is a logical architecture. Docker is not required (p. 30, 93).
- A business microservice may be several processes or containers, for example a Web API plus a search service. These may share one data model when they are cohesive around the same domain (p. 30-31).
- What must hold is autonomy: code and state are versioned, deployed and scaled independently (p. 30).

### Distributed data challenges (p. 31-35)
- **Queries across services** (p. 32-33). The book lists three options:
  - An API gateway that aggregates. Beware that it can become a choke point and hurt autonomy.
  - CQRS read tables, also called materialized views. These are denormalised tables built in advance from other services' data, shaped for one screen. They cost dev work and mean eventual consistency.
  - "Cold data" exported to a central reporting store. Use it only for queries that don't need real-time data. The source of truth stays in the services.
- If you **constantly** need to aggregate across services for normal operations, the design may be wrong, and merging services may be the fix. Reporting is excluded from this rule (p. 33).
- **Consistency across services** (p. 33-34):
  - No service may include another service's tables in its own transactions, or even query them (p. 33).
  - Propagate changes with integration events and eventual consistency. Most systems choose availability over strong consistency (CAP) (p. 34).
  - Two-phase commit is against microservice principles and unsupported by most NoSQL stores (p. 34).
- **Communication style** (p. 35-36):
  - Long chains of synchronous HTTP calls between services cause blocking, coupling, and failure of the whole chain when one link fails (p. 35).
  - The book says such a chain is effectively a monolith that talks over HTTP (p. 35).
  - Minimise request/response chains. Integrate asynchronously, by messages or by polling outside the original request (p. 36).

### API gateway vs direct client-to-microservice (p. 40-48)
- Direct client calls can be enough for small systems or a server-side web client (p. 40).
- For SPAs, mobile apps or dozens of services, direct calls bring four problems: the client is coupled to the internal decomposition, a screen needs many round trips, every service is exposed (bigger attack surface), and each service must handle SSL and auth itself (p. 41-42).
- A gateway is a single entry point for a **group** of services: a distributed facade. The book also calls it a backend-for-frontend (BFF) (p. 42).
- **Don't build one gateway for everything.** A single custom gateway grows into a monolith and couples all services. Split it per client type (BFF) and, in larger systems, per business area (p. 43-44, 164).
- The core features are:
  - Routing (a reverse proxy) (p. 44). Routing also helps strangle a legacy monolith, because clients don't notice which backend serves a URL.
  - Request aggregation (p. 45). This matters for remote clients and much less for server-side web apps. Aggregation in code, as an aggregator service behind the gateway, is more flexible than gateway configuration (p. 45, 175).
  - Offloading cross-cutting concerns such as auth, caching, retries and circuit breakers, rate limiting, and logging/correlation (p. 45).
- A product gateway (API management) is "thinner" because it holds no custom code, so a single instance is less risky (p. 46).
- Drawbacks:
  - The gateway couples to internal services (the book calls this risk "the new ESB").
  - It is another single point of failure and adds latency.
  - It can become a bottleneck if not scaled.
  - Custom aggregation code costs development and maintenance.
  - If one team owns it, that team becomes a bottleneck (p. 47-48).
- An Ingress (for example Nginx in Kubernetes) only forwards HTTP and hides nothing. The book's "ideal" setup is an Ingress in front, with several gateways behind it (p. 180-181).

### Communication types (p. 48-58)
- Turning in-process calls into one RPC each gives chatty, slow systems. Group calls into coarser messages instead (p. 48).
- The book follows "smart endpoints and dumb pipes": choreograph with REST and events, not with a central process orchestrator (p. 49).
- There are two axes: sync vs async protocol, and single vs multiple receivers. Multiple receivers is always async pub/sub (p. 49).
- **The key rule.** Communication between services should be async in the sense of not depending on another service inside your own request/response (p. 50).
  - The book's wording: "If possible, never depend on synchronous communication... not even for queries" (p. 50).
  - If you need another service's data, **replicate the attributes you need** into your own DB via integration events. Don't fetch them on each request (p. 51).
  - Duplicating data is fine. It lets you translate the data into your own BC's language, as the user becomes a Buyer in ordering (p. 51).
  - Any transport works for this propagation, even HTTP polling. What matters is no synchronous dependency (p. 52).
- Request/response over HTTP suits real-time UI queries from clients (p. 52-53). Use push (SignalR or WebSockets) for one-to-many live updates (p. 53-54).
- Use async messaging between internal services, and synchronous HTTP only from clients to the front tier: gateways and the first level of services (p. 55).
- **Single-receiver messages (commands):**
  - Delivery can repeat after failures, so the receiver must be idempotent (p. 55).
  - Once you use messages, don't mix them with synchronous HTTP in the same flow (p. 55).
  - Commands from clients can stay as HTTP (p. 56).
- **Multiple receivers (pub/sub):** the sender doesn't change when a new subscriber is added. This is the open/closed principle at system level (p. 56).
- **Make eventual consistency explicit to users and the business.** Don't fake immediacy with client polling or push that mimics events (p. 56).
- **Choice of messaging tech** (p. 57-58, 134-135):
  - A hand-made bus over RabbitMQ is a proof of concept.
  - For production, evaluate a service bus library. The book names several, and lists Rebus among the open-source options (p. 141).
  - Building your own bus features on a raw broker "might cost too much".
- **Atomic update and publish** (p. 58): the options are a DTC queue (legacy), transaction-log mining, full event sourcing, or the **outbox** (a transactional table used as a queue). Details are in Ch. 5 below.

### API versioning (p. 59)
- The contract is the URLs plus the JSON for HTTP, and the message types for messaging (p. 59).
- Small additive changes should keep old clients working: give defaults for new required inputs and have clients ignore extra fields (p. 59).
- For breaking changes, run old and new versions side by side for a while, with the version in the URL or a header. The book suggests the mediator pattern to keep version handlers apart (p. 59).

### Other topics: addressability, composite UI, resilience, health (p. 60-65)
- Services need stable names resolved by a registry. Orchestrators such as Kubernetes provide this (p. 60).
- Micro-frontends (composite UI) are possible, but the sample deliberately keeps one monolithic UI (p. 60-62).
- Resilience covers compute (restart anywhere) and state (no loss, still consistent). Rollouts must be able to stop or roll back based on health signals (p. 63).
- Health is not diagnostics. Liveness asks "can it answer requests?"; readiness asks "are its dependencies (DB, queue) ready?" (p. 63-64).
- Teams must agree on one log format. Services write logs to stdout and let the platform collect them (p. 64).

---

## Ch. 5 - Designing services; integration events (p. 93-163)

### Choosing an architecture (p. 93-102)
- The sample uses HTTP through gateways for client queries and commands, and an event bus to propagate updates between services (p. 96).
- Each service has its own DB. Cross-DB consistency comes from integration events, so the business rules must accept eventual consistency (p. 95).
- The downsides the book lists are:
  - distributed complexity and latency
  - deployment complexity
  - no atomic transactions across services
  - more total resources
  - the client/API mismatch that gateways solve (p. 98-99)
- Partition by use case. Each service has few responsibilities: SRP at service scale (p. 99).
- **Internal architecture may differ per service.**
  - Simple services stay CRUD.
  - Services with ever-changing rules get DDD.
  - Putting DDD on a CRUD service is over-engineering, and putting complex rules into a CRUD design gives low-quality code (p. 99-100).
  - CQRS is never a top-level architecture for the whole system (p. 102).

### CRUD service notes (p. 102-132)
- A CRUD service is a single Web API project holding the model, logic and data access. eShop's Catalog is the example (p. 102).
- Migrating and seeding at container startup must retry until the DB is reachable (p. 130).
- The EF in-memory provider does not enforce DB constraints such as unique indexes. Use a real DB for accurate integration tests (p. 132).

### Integration events (p. 133-136)
- An integration event syncs domain state across services or external systems. It is a plain data class (p. 135).
- **Don't share one integration-events library across services.** It couples them the way a shared domain model would. Define events per service, the way ViewModels are defined (p. 135).
- Size events to be "just right" for consumers. Avoid both bloated and data-deficient messages (p. 135).
- Shared libraries are acceptable only for the final infrastructure blocks, such as the bus client API, and for generic tools such as serializers (p. 135).
- With a richer service bus, use its abstractions directly rather than wrapping them in your own (p. 137).

### Publishing atomically: outbox and event log (p. 142-147)
- Saving and then publishing in two steps "does not take atomicity into account". A crash in between leaves the system inconsistent (p. 142-143).
- **Distributed transactions are not recommended** (CAP) (p. 143).
- The options the book weighs (p. 143-144):
  - Full event sourcing: arguably the best, but it means a rearchitecture.
  - Transaction log mining: couples you to the DB internals, and low-level row changes don't map to business events. Probably not desirable.
  - The **chosen middle path**: an integration-event table in the **same DB and same local transaction** as the business change, with a state per event (ready to publish / published).
- Recipe: begin a local transaction → change entities + insert event row → commit → publish → mark the row as published (p. 144).
- **Variant A:** publish right after commit and use the table as a log.
  - It needs a separate checker that republishes unconfirmed rows.
  - eShop uses A and skips the checker for simplicity (p. 145-146).
- **Variant B:** the table is the queue. A worker reads it, publishes, and marks rows.
  - The table is the single source of outgoing events, so the book calls this more effective (p. 145-146).
  - A real cloud app must implement this check-and-resend (p. 146).
- One local transaction can span two DbContexts: business and event log (p. 146). Wrap it in the EF execution strategy so connection retries replay the whole unit. This is the "ResilientTransaction" helper (p. 296-298).

### Idempotency and deduplication (p. 149-151)
- Duplicates are inevitable: retries, a republishing job, redelivery. Handlers must be idempotent, or carry enough data to detect and drop a duplicate (p. 149).
- The ways the book lists:
  - Natural idempotency, such as an insert-if-not-exists (p. 149).
  - **Absolute state instead of deltas.** "Set price to 25" is replay-safe and "add 5" is not. The book notes the caveat that an old message replayed late can still overwrite a newer value (p. 149-150).
  - An identity per event, processed once per receiver (p. 150).
  - Special care for side effects that are not idempotent, such as charging a card (p. 150).
- Dedup at both levels, the transport feature plus handler logic, is "your best bet" (p. 150).
- In eShop, the handler wraps the command in an IdentifiedCommand keyed by the event's request id (p. 150, 282-285).
- RabbitMQ sets a "redelivered" flag. Without it, the message is guaranteed to be first delivery, so dedup is needed only when the flag is set. Idempotent handling is still preferred over explicit dedup (p. 151).

### Testing and background work (p. 152-163)
- The four test types are unit, integration (real infrastructure), functional (one service, from the user's view), and service tests (across services, environment started first) (p. 152-156).
- Integration tests are much slower than unit tests, so keep fewer of them. TestServer runs the HTTP pipeline in process (p. 154).
- Use `IHostedService`/`BackgroundService` for background work, not raw threads. You get graceful start and stop (default shutdown timeout 5 s) (p. 159-162).
- If the work has nothing to do with HTTP, use a plain host. Background work can be its own scalable process (p. 157-159).

---

## Ch. 6 - DDD and CQRS inside one service (p. 182-290)

### Simplified CQRS (p. 184-193)
- CQRS here is the **simple** version: one database, two logical models. Queries are side-effect free and commands go through the domain model. There is no separate read DB and no event sourcing (p. 184-185).
- Apply DDD patterns only on the command/write side. Aggregates add only complexity to read queries (p. 187).
- Queries bypass the domain model. They use a micro ORM (Dapper), join any table, and return ViewModels shaped for the UI (p. 188-190).
  - The cost: when the persistence model changes, the raw SQL must be updated separately (p. 187).
- Dynamic ViewModels are quick to write, but they hurt client compatibility and Swagger docs. Static DTOs are better for long-lived APIs. The book suggests starting dynamic and then moving to explicit DTOs (p. 190-191).
- Annotate actions with `ProducesResponseType` so Swagger shows the response shape (p. 192).
- CQRS and DDD describe the inside of one component and are not system architectures. Forcing one pattern on every BC "leads to failure" (p. 187-188).

### Layers in a DDD service (p. 194-199)
- Choosing boundaries balances small services against chatty calls. Split until the communication between services starts to grow fast. If two services collaborate heavily, they probably belong together (p. 195).
- The three layers are application (Web API: thin, coordinates, holds no business rules), domain (rules and state, depends on nothing), and infrastructure (persistence). Dependencies point toward the domain (p. 196-198).
- Entities never reach the presentation layer. Use ViewModels or DTOs, because entities must always be valid and UI data may not be (p. 196).
- Persistence ignorance does not mean ignoring the physical model. An impossible-to-store model is still a bad model (p. 197).

### Entities, aggregates, aggregate roots (p. 199-213)
- An entity is defined by identity and continuity. Behaviour (invariants and rules) lives in entity methods, not in services (p. 199).
- **Anemic model:** getters and setters with all logic in services.
  - It is acceptable for simple CRUD (p. 200).
  - It is likely an anti-pattern when rules are many and change often. Logic piling up in service classes is the warning sign (p. 200-201).
- An **aggregate** is the cluster that must be consistent together at the end of one transaction. Find aggregates by looking at transactions, not by drawing groups (p. 202, 205).
- The **aggregate root** is the only entry point for changes and guards the invariants. Changing children directly is like "a table with a loose leg" (p. 202-203).
- Aggregates reference each other **by id only**, with no navigation property (p. 203).
- How to encapsulate:
  - Expose collections read-only, with no public setters.
  - Change state through intent-named methods. eShop's `AddOrderItem` merges duplicate lines and applies the better discount (p. 207-209).
  - Do not build child entities in a command handler or controller (p. 208).
- **Seedwork** is a few copy-in base classes (Entity, ValueObject, Enumeration, IRepository, IUnitOfWork). The book stresses it is not a framework (p. 210-211).

### Value objects (p. 213-221)
- A value object has no identity, is compared by value, and is immutable. Whether something is an entity or a value object depends on the context (p. 201, 214).
- Persist value objects as EF Core **owned types** (`OwnsOne`). By default they are stored as columns in the owner's table (p. 218-219).
- Owned-type limits: no DbSet, no inheritance, and no optional owned type when table-split (p. 220-221).

### Enumeration classes vs enums (p. 221-223)
- Plain enums suit one value from a closed set. Using enums to drive control flow scatters checks around the code, which is a smell (p. 221).
- An `Enumeration` base class lets the members carry behaviour. The book says this is optional, and plain enums are fine for simplicity (p. 222).

### Validation (p. 223-227)
- Entities are always valid. Validate in constructors and mutating methods and throw on a violation (p. 223-224).
- Mutations must be all-or-nothing, so never leave an entity half-changed (p. 224).
- Data annotations belong on DTOs and ViewModels, not entities (p. 224-225).
- Validate in two steps: field rules on the command/DTO, invariants in the entity. Use the Notification pattern to collect several errors instead of failing on the first (p. 225).
- Client validation is UX only. Always revalidate on the server (p. 226).

### Domain events vs integration events (p. 227-238)
- A **domain event** is in process, within one BC. It makes side effects across aggregates explicit and is dispatched in memory, for example by a mediator (p. 227-228).
- An **integration event** crosses services, is always async, and is published only after the change is persisted (p. 228-229).
- Domain-event handlers live in the application layer, since they use repositories (p. 230). A domain-event handler may emit an integration event (p. 237).
- A command is handled once. A domain event has zero to n handlers, so new rules become new handlers instead of edits to tested code (p. 230-231).
- **Don't dispatch from a static `Raise` at once.** Collect events on the entity and dispatch them at save time (p. 232-234).
- When to dispatch:
  - Before commit: the side effects share one transaction. This is the simplest choice with EF and a relational DB, and eShop uses it (p. 234-236).
  - After commit: several transactions, so you must accept eventual consistency and write compensation (p. 234).
- **One transaction per aggregate vs spanning aggregates:**
  - The book says both camps can be right.
  - Decide by business need, scale, and how much code you'll invest. Eventual consistency costs detection and compensation logic (p. 234-236).

### Repositories and unit of work (p. 238-254)
- **One repository per aggregate root, not per table.** It is the only update channel for that aggregate (p. 239).
  - Reads may bypass it (CQRS queries) (p. 239).
  - Enforce the rule by constraining `IRepository<T>` to `IAggregateRoot` (p. 240-241).
- A repository holds updates plus only the loads needed for an update. Presentation queries live elsewhere (p. 247).
- `DbContext` **is** the unit of work, so don't wrap its change tracking again (p. 241, 248).
  - DbContext and repositories must be Scoped. A Singleton repository holding a scoped context causes concurrency bugs (p. 248-249).
- Repositories are optional.
  - Using `DbContext` directly is fine for CRUD services (p. 247).
  - The book quotes the opposing view that repositories add little, especially with CQRS. It concludes that aggregates and a rich model matter more than repositories (p. 242-243).
- Map with the Fluent API (`IEntityTypeConfiguration` per entity), not annotations on entities (p. 250-251).
- Don't return `IQueryable` from a repository. The Specification pattern bundles criteria, includes and paging (p. 253-254).
- A document store can hold a whole aggregate as one document. Don't expect one model to fit both relational and NoSQL stores (p. 255-256).

### Commands, handlers, MediatR (p. 266-290)
- A command is an imperative request that may be refused. It goes to one receiver, is sent rather than published, is immutable, and carries exactly the needed data (p. 272-275).
- A command handler is the heart of the application layer but holds no domain logic. Its steps: validate, load the aggregate, call its method, persist. It usually touches one aggregate, and others react via domain events. A complex handler is a smell (p. 275-277).
- Calling handlers directly from controllers is "too coupled and not ideal". The book prefers an in-memory mediator, or a queue for scale (p. 278).
- The mediator's value is a pipeline of behaviours for cross-cutting concerns. eShop has logging and FluentValidation behaviours. The book calls this explicit, debuggable AOP (p. 279, 287-289).
- **Never use fire-and-forget commands.** The client must learn whether a command succeeded or was at least accepted (p. 280).
  - Async commands need their own failure-reporting path. The book says they are arguably events anyway (p. 280-281).
  - eShop uses synchronous HTTP commands through the mediator (p. 281).
- Idempotent commands use `IdentifiedCommand`: the request id is stored and repeats return a default result. Note that eShop's version swallows exceptions (p. 282-285).

---

## Ch. 7 - Resilience and health (p. 291-318)
- Partial failure is certain. Long synchronous chains amplify it: one slow dependency uses up threads, and the book shows how many 99.99% dependencies add up to hours of downtime a month (p. 292-293).
- The strategies are:
  - async integration between internal services
  - retries with exponential backoff
  - timeouts on every call
  - circuit breakers
  - fallbacks (easy for queries, hard for commands)
  - bulkheads that cap queued requests (p. 294-295)
- Retries without a circuit breaker can turn into a self-inflicted DoS. Add **jitter** to spread retry storms (p. 294, 305-306).
- A circuit breaker stops calls that are likely to fail. Retry logic must respect an open circuit (p. 306-307).
- Enable the EF Core retrying execution strategy. With explicit transactions, run the whole unit through `CreateExecutionStrategy` (p. 295-298).
- Use `IHttpClientFactory` (typed clients) rather than creating `HttpClient` per call, which exhausts sockets, or one static instance, which goes stale on DNS changes. Attach retry and circuit-breaker policies as handlers (p. 298-304).
  - Don't copy the sample's retry policy as-is: it also retries on 404.
- Health checks: `AddHealthChecks` plus a check per dependency. Keep them cheap, because orchestrators poll often (p. 311-314).

## Ch. 8 - Security, brief (p. 319-333)
- Authentication is usually central: at a gateway, or by an identity service that issues tokens the services trust (p. 319-320).
- If services are reachable without the gateway, they must authenticate requests themselves (p. 319). Each service should still enforce `[Authorize]` and validate its own audience (p. 178).
- SPAs and APIs use bearer tokens. Validation checks the authority, audience and signature (p. 323-327).
- Authorization is role-based or, more flexibly, policy-based with custom requirements and handlers (p. 327-330).
- Never commit secrets. Use environment variables or a secret manager in dev and a vault in production (p. 330-333).

## Ch. 4 and orchestration, brief (p. 1-92, 66-71)
- Containers make deployment repeatable, and orchestrators handle scheduling, scaling, discovery and health (p. 66-71).
- Don't run production databases in containers (p. 97).
- Keep environment differences in config, not in the base compose file (p. 121-123).

---

## Repo mapping

| Book concept | Book's guidance (short) | Repo today (file/doc/tag) | Verdict | Note |
|---|---|---|---|---|
| Data sovereignty | Each service owns its DB. Others go through API or messages, never the tables (p. 27-29, 33) | Own Postgres per service. "No cross-service DB connections" and a project reference to another service is "Illegal!" (ghost standing decisions, [CROSS-SERVICE], [REUSE-FIRST]). `SERVICE_ARCHITECTURE.md`: never query ServiceC's DB | fits | — |
| Replicate what you need | Propagate only the needed attributes into your own DB via events, and rename them in your own language (p. 51) | `CODING_STYLE_BACKEND.md` Event Flow Example (UserEvent → replicas in ServiceA/ServiceB/ServiceD/ServiceE). ServiceContractEvent replicas. [BUS-IS-NOT-RPC] "replicate what you need" and handle deletion events | fits | Repo adds a rule the book lacks: re-check read authorization on replicated data |
| No sync calls between services | "never depend on synchronous communication... not even for queries" (p. 50). Async only between internal services (p. 55) | Resource services call ServiceC over HTTP for every authorization decision (`SERVICE_ARCHITECTURE.md`, [AUTHZ-OWNER]). Replicating permissions over the bus is explicitly rejected | **conflicts (deliberate)** | Standing decision wins. It makes ServiceC a hard runtime dependency, so the book's Ch. 7 mitigations apply to the ServiceC client. Repo has a role/permission cache ([CACHE-INVALIDATION]) |
| No sync calls from handlers | Don't chain requests. Once in a message flow, don't mix in sync HTTP (p. 35, 55) | "Never Synchronously Call Other Services from Handlers" (`CODING_STYLE_BACKEND.md`) | fits | Same reasoning (temporal coupling, retry floods) |
| Async commands / request-reply messages | Single-receiver command messages and reply messages are legitimate (p. 54-56). Async commands are allowed for scale but need a failure path (p. 280-281) | [BUS-IS-NOT-RPC] forbids request/response over the bus, and [EVENT-PAYLOAD] forbids "an API whose only job is to send a message to its own worker". Entity events, not one-off commands | **conflicts with a standing decision (Repo stricter)** | Both agree on "never fire-and-forget" (p. 280) ↔ "a 200 OK will not mean processing is finished" (2025-11-24) |
| Message shape | Absolute state, not deltas. Size "just right" (p. 135, 149) | A message is the whole row state with `UpdatedAt`. Data consumers upsert by timestamp and ignore event type ([EVENT-PAYLOAD], [EVENT-IDEMPOTENCY]) | fits (Repo stronger) | Repo's timestamp compare fixes the book's own caveat about an old replay overwriting newer state (p. 149-150) |
| Shared event contracts | Don't share one integration-events library across services (p. 135) | Events live in shared `Repo.Shared.Messaging.Messages` and inherit `BaseEvent` (`CODING_STYLE_BACKEND.md` Conventions) | **conflicts with the book** (not with a standing decision) | Repo chose shared typed contracts and enum routing keys. The book's risk is real: a shape change in one service has broken consumers ([EVENT-PAYLOAD], 2024-03 freeze). Treat any event-shape change as a contract change |
| Idempotent handlers | Required. Natural idempotency, absolute state, event id, extra care for non-idempotent effects (p. 149-150) | "Idempotent Event Handlers (CRITICAL)": upsert `ON CONFLICT`, unique constraints, dedupe by `BaseEvent.Id`. [EVENT-IDEMPOTENCY]: decide from local replica, not from `EventType` | fits | — |
| Deduplication | Do it at both transport and handler level (p. 150-151) | Rebus has no transport dedup, so Repo relies on idempotent handlers. Billing dedupes on (Metric, SourceId). Outbound sends use a table as an atomicity check ([EVENT-IDEMPOTENCY] 2026-09-14) | partly | Handler-level only. That is acceptable, since the book itself prefers idempotency over dedup (p. 151) |
| Outbox / atomic publish+commit | Two-step save-then-publish is not atomic. Use an event table in the same local transaction, plus a checker or a table-as-queue worker (p. 143-146) | `CODING_STYLE_BACKEND.md` "Transactional Outbox (When to Consider)": only for critical transitions. One real outbox exists: `ServiceD.API/Services/MessageSentOutboxDispatcher.cs` (polls, publishes, deletes; service-private). [PUBLISH-AFTER-COMMIT]: publish after commit, and at minimum log publish failures. 2026-03-11: inbox/outbox for cascades | partly | Most Repo publishes are the book's naive variant. The safety net is full-state events, which let the next event repair a miss. The ServiceD dispatcher is the book's variant B. The dispatcher says ServiceB should generalise it into the shared messaging layer |
| Distributed transactions | Not recommended (CAP) (p. 34, 143) | None used | fits | — |
| Eventual consistency made explicit | Make it visible to users and the business. Don't fake it (p. 56) | Writes stay synchronous inside the owning service, and only replication is async ([BUS-IS-NOT-RPC] 2025-11-24) | fits | — |
| Out-of-order and poison messages | The book is mostly silent beyond idempotency | Replicated FK stays non-null, and out-of-order delivery is fixed by replay (2025-12-01). Error queue at zero tolerance (2026-02-11). [PUBLISH-AFTER-COMMIT] covers events about entities consumers never saw | Repo beyond book | Use the Repo rules here, since the book gives none |
| Data fixes vs events | Events are raised by application code when state changes (p. 142-146) | [DATA-FIX-ROUTE]: a producer-side migration emits no events (roles never reached ServiceD). Go through the API, or bump `UpdatedAt` and republish | Repo beyond book | A direct consequence of the book's model that the book never spells out |
| API gateway / BFF | Use gateways split per client and per business area. Aggregation services behind them. Ingress alone hides nothing (p. 40-48, 164, 175, 180) | AWS ALB Ingress path routing `/api/{service}` straight to each API (`infra/k8s/shared/03-ingress.yaml`). No gateway or aggregator. "No BFF or client stitching": the owning service enriches from its replicas (2025-12-03, [BUS-IS-NOT-RPC], [EVENT-DRIVEN-BOUNDARY]) | **conflicts with a standing decision** | Repo moves aggregation into the owning service through replicas. That matches the book's materialized-view option (p. 32-33), not its gateway option |
| Auth at the edge vs per service | Authenticate centrally, but each service still enforces `[Authorize]` and validates its audience (p. 178, 319) | Each service validates the JWT itself via `AddRepoWebApi`. Authorization is ServiceC actions, not local roles or policies ([AUTHZ-OWNER], [PERMISSION-PLACEMENT]) | partly | Authentication fits. Authorization is more central than the book's role/policy-per-service model |
| Logical vs physical service | One BC may run as several processes over the same data (p. 30-31) | `ServiceA.API`, `ServiceA.Sync.API`, `ServiceA.Advisory.API` and many `ServiceA.Worker.*` share `ServiceA.Domain`. ServiceB API plus workers likewise | fits | Workers are side doors, so rules that must hold everywhere go in Domain (`lift-the-gaze/references/layers.md`) |
| Merge chatty services | If services constantly need each other, merge them (p. 33, 195) | Org + user + auth merged into ServiceC (2025-01-02, [EVENT-DRIVEN-BOUNDARY]). But new features go to the owning service, not ServiceC, "our wannabe monolith" (2026-02-11, [CROSS-SERVICE]) | fits | — |
| Reporting store | Export "cold data" to a reporting DB fed by events (p. 33) | ServiceE subscribes to events and computes its own reporting data (`CODING_STYLE_BACKEND.md` Event Flow; "service-e is not migrated... its computed", 2026-09-28) | fits | — |
| Internal architecture per service | CRUD where simple, DDD where rules are complex. Don't force one pattern (p. 99-102, 187) | One shape everywhere: Controller → Service → Repository (`CODING_STYLE_BACKEND.md`). A controller may call a repository directly "when it makes sense" ([REPO-PATTERN], 2025-10-08) | partly | Uniform layering, with pure rules pulled into `*.Domain/Policies`. No rich aggregates |
| Simplified CQRS / Dapper reads | Commands through the domain model, queries with Dapper straight to SQL (p. 184-190) | EF Core plus Dapper; "heavy SQL is done with Dapper" (2026-02-24). No formal command/query split. No stored procedures ([NO-STORED-PROC]) | partly | Same split in practice for heavy reads |
| MediatR command pipeline | Commands, handlers and mediator behaviours for logging and validation (p. 271-289) | Not used (no MediatR reference in `services/` or `shared/`). Services are called from controllers and handlers | **conflicts if introduced** | [REUSE-FIRST] "backend, follow what we have" and [NECESSITY] argue against adding it. Cross-cutting concerns come from `AddRepoWebApi` |
| Domain vs integration events | Domain events in process, dispatched at save. Integration events after commit (p. 227-238) | No in-process domain events. Services publish integration events through domain publishers (`UserEventPublisher`). [PUBLISH-AFTER-COMMIT]: publish from the place that commits | partly | The book's "after commit" rule for integration events matches [PUBLISH-AFTER-COMMIT] exactly |
| Repository per aggregate root | One repo per root as the only update path. DbContext is the unit of work (p. 239-248) | Repositories per entity/table in `*.Domain/Repository`. Entities are the DB shape (`layers.md`). Scoped DI matches the book (p. 248-249) | partly | Anemic entities are fine by the book for CRUD-like services (p. 200). They become a smell where rules pile up in services ([ONE-HOME-FOR-A-RULE]) |
| Enumeration classes | Optional. Enum-driven control flow is a smell (p. 221-222) | "Prefer enums over boolean flags". Enums over strings ([ENUM-OVER-STRING]). ProductType is moving from an enum to data ([PRODUCT-IS-DATA]) | partly | Both warn against branching on enums. Repo's fix is data, not behaviour classes |
| Validation | Field rules on DTOs, invariants in the entity, server always revalidates (p. 223-227) | Validate at the controller boundary, plus a DB constraint "so its totally impossible" and returning 400 ([BAD-INPUT-IS-4XX]). FluentValidation is allowed for complex cases | partly | Repo puts invariants in the DB and Domain/Policies, not in entity methods |
| Versioning | URL or header versions, additive changes, run old and new side by side (p. 59) | `api/{service}/v{version}` via `ApiVersioningExtensions`. [EXPAND-CONTRACT] for schema changes during rolling deploys | fits | The book covers APIs. Repo also applies the same rule to DB schema during rollout |
| HTTP resilience | Typed clients via `IHttpClientFactory` with retry, jitter, circuit breaker and timeouts (p. 294-310) | `AddHttpClient()` in services. No Polly or resilience handler found in `services/` or `shared/` | **gap** | Matters most for the sync ServiceC authorization calls |
| Messaging retries | Retry, then park (p. 140, 294) | Rebus retries (`Rebus:MaxDeliveryAttempts`, default 5) and then `{service}-error`. Handlers re-throw ([FAIL-LOUD]) | fits | — |
| Health checks | Liveness and readiness. Cheap checks per dependency (p. 63-64, 311-317) | `/health` with an Npgsql check (`WebApplicationExtensions.cs`). K8s liveness/readiness probes in `infra/k8s/*/03-deployment.yaml` | fits | Readiness does not cover RabbitMQ unless a check is added |
| Secrets and orchestration | Use a vault and an orchestrator (p. 330-335) | AWS Secrets Manager ([SECRETS-CONFIG]), EKS plus Terraform ([DEPLOY-PIPELINE]) | fits | — |
| Strangling a legacy monolith | Put gateway routing in front of the old API and move endpoints out (p. 44) | The SignedIn → Nova move goes through data migrators ([MIGRATOR-PARITY]) and flags with a go-live date | partly | No gateway strangler, so the book's routing trick does not apply |
| Feature switches | Not covered | [CONTRACT-IS-THE-SWITCH]; frontend PostHog release flags | n/a | The book has no guidance |

---

## Questions this source helps answer

1. **Should service B call service A synchronously, or replicate A's data via events?** Replicate the attributes you need (p. 50-52, 33-34). Repo exception: authorization always goes to ServiceC over HTTP ([AUTHZ-OWNER]), so harden that client (Ch. 7, p. 294-310).
2. **Where does a new capability belong, and when should two services merge?** Boundaries by BC and vocabulary (p. 31-32, 36-39). Merge when services constantly need each other (p. 33, 195).
3. **Is it OK for one service to have several deployables over the same DB?** Yes: logical vs physical architecture (p. 30-31).
4. **A screen needs data from three services. Gateway aggregator, client stitching, or a local copy?** The options are on p. 32-33 and 40-48. Repo picks the materialized-view style (replicas in the owning service) over BFF/aggregators (2025-12-03).
5. **How do I guarantee that a DB write and its event both happen?** The outbox/event-log options (p. 58, 142-147) and the resilient transaction (p. 296-298). Compare with Repo's "when to consider" and `MessageSentOutboxDispatcher`.
6. **How do I make a handler safe for duplicates and replays?** p. 149-151 (absolute state, event id, the redelivered flag). Then Repo's upsert-by-`UpdatedAt` rule.
7. **Should events carry deltas, ids only, or full state?** The "just right" payload and absolute state (p. 135, 149). Repo's answer is full row state.
8. **Should event contracts be shared across services?** The book says no (p. 135). Repo shares them. Weigh the coupling before changing a shape.
9. **Domain event or integration event, and dispatch before or after commit?** p. 227-238.
10. **Does this service need aggregates and rich entities, or is CRUD enough?** p. 99-102, 187, 200-201. Signs you need more: logic piling up in services, invariants enforced in several places.
11. **One repository per table or per aggregate, and do we need repositories at all?** p. 239-248 (DbContext is the unit of work, repos are optional).
12. **What resilience does an outbound HTTP call need?** Timeout, retry with jitter, circuit breaker, bulkhead (p. 294-310). Health checks and readiness (p. 63-64, 311-317).
