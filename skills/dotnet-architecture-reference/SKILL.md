---
name: dotnet-architecture-reference
description: Generic .NET architecture knowledge (layering, clean architecture, DDD aggregates, CQRS, microservice boundaries, data per service, integration events, outbox, idempotency, API gateway, resilience) distilled from Microsoft's architecture eBooks and mapped onto Repo with fits / partly / conflicts verdicts. A reference, not a workflow. Load it from lift-the-gaze or when someone asks "how is this usually done in .NET", "what does clean architecture / DDD / the microservices guide say", "should this be an aggregate / event / outbox / gateway", or wants to compare Repo's architecture with the textbook.
user_invocable: true
---

# .NET Architecture Reference

Generic knowledge, kept separate from the codebase's own rules so it never overrides them.

## Precedence (always apply)

1. **The codebase's standing decisions:** for Repo, `~/.claude/commands/ghost-review.md` and `owl-review.md`, the "Standing decisions" sections and tags.
2. **The repo's docs:** `docs/CODING_STYLE_BACKEND.md`, `API_CONVENTIONS.md`, `SERVICE_ARCHITECTURE.md`.
3. **This reference.**

When the textbook disagrees with 1 or 2, show both. Quote the decision with its date and say why the codebase chose differently. Never recommend the textbook over a standing decision. If a doc lags a newer standing decision, say so. Example: `CODING_STYLE_BACKEND.md` "Do not skip layers" lags the 2025-10-08 controller→repository agreement.

## Sources

| File | Source | Page refs |
|---|---|---|
| `sources/ms-architecting-modern-web-apps.md` | *Architecting Modern Web Applications with ASP.NET Core and Azure* (Microsoft, 2023). One app: principles, layers, clean architecture, MVC, EF Core, testing. | **PDF** pages (printed ≈ PDF − 9) |
| `sources/ms-dotnet-microservices.md` | *.NET Microservices: Architecture for Containerized .NET Applications* (Microsoft, 2023). Boundaries, data sovereignty, communication, integration events, outbox, DDD, CQRS, resilience. | **Printed** pages (PDF = printed + 15) |
| `sources/cognitive-load.md` | *Cognitive load is what matters* (github.com/zakirullin/cognitive-load, commit `d2d60d2`, June 2026). Shallow vs deep modules, layers that add only indirection, nesting, inheritance, DRY abuse, shallow microservices, self-describing result codes. **CC BY 4.0**: credit and link the licence when reusing. Shared in #knowledge-sharing 2024-06-20. | README section headings |
| `sources/knowledge-sharing.md` | Five articles from Slack #knowledge-sharing (code review guide, twelve-factor, outbox/inbox, DB replication, OTel baggage), each with takeaways and Repo relevance. | Article URL per section |

Both books are "all rights reserved". The digests are in our own words with page refs. Don't paste book passages into anything that gets published.

## Where to look

| Question | Read |
|---|---|
| Where does this logic belong: Domain project, API service, controller? | web-apps Ch. 3-4 + mapping; microservices "Layers in a DDD service" |
| Is Repo's `*.Domain` "clean architecture"? | web-apps mapping, row on core vs infrastructure. **Partly:** Domain holds DbContext + migrations |
| Repository per entity or per aggregate? Specification pattern? | web-apps Ch. 7; microservices "Repositories and unit of work" |
| Should service B call A synchronously, or replicate A's data via events? | microservices "Communication types", "Data sovereignty", "Distributed data challenges" |
| Integration event vs domain event, and what goes in the payload? | microservices "Domain events vs integration events", "Integration events" + [EVENT-PAYLOAD] |
| Do we need an outbox here? | microservices "Publishing atomically: outbox" + CODING_STYLE_BACKEND "Transactional Outbox" |
| How do we make a handler idempotent? | microservices "Idempotency and deduplication" + [EVENT-IDEMPOTENCY] |
| Gateway, BFF or direct client→service? | microservices "API gateway vs direct client-to-service". Repo ruled out BFFs (2025-12-03) |
| CQRS / MediatR? | microservices "Simplified CQRS", "Commands, handlers, MediatR". **Not used** in Repo; adding it hits [NECESSITY] |
| Value objects, enumeration classes vs enums? | microservices "Value objects", "Enumeration classes vs enums" |
| Retries, circuit breakers, health checks? | microservices Ch. 7. Repo has **no Polly/resilience handler** on HttpClients (verified 2026-10-17); ServiceC calls matter most |
| How to test at which level? | web-apps Ch. 8 + ghost [MISSING-TEST] / integration-test sparsity |
| Does this service/layer/interface earn its place, or is it just indirection? | cognitive-load "Layered architecture", "Too many small modules" + mapping rows on [REPO-PATTERN] and one-implementation interfaces. **Conflict:** `CODING_STYLE_BACKEND.md:85` mandates an interface per service |
| Base class with override hooks, or compose? | cognitive-load "Inheritance nightmare" + Billing/ServiceE mapping row |
| Merge two similar code paths? | cognitive-load "Abusing DRY" + [ONE-HOME-FOR-A-RULE]: merge rules, not look-alike code, never via a mode flag |
| Is this code too nested / too clever to review? | cognitive-load "Nested ifs", "Complex conditionals", "Familiar projects" + ghost 2026-05-13 nested-if quote |
| New microservice or extend an existing one? | cognitive-load "Too many shallow microservices" + 2025-01-02 ServiceC merge; microservices "Bounded contexts and boundaries" |
| What should a reviewer approve, and how to mark non-blocking comments? | knowledge-sharing "Google engineering practices" |
| Outbox vs inbox, and how to survive redelivery? | knowledge-sharing "Microservices 101" + microservices "Publishing atomically: outbox" |
| Pass context (retailer, flag) across services without drilling parameters? | knowledge-sharing "OpenTelemetry baggage". Never PII, never authorization |

## Repo vs textbook, with evidence

`repo-vs-textbook.md` covers 25 topics. Each one gives what the textbook says (with page), what Repo's code does (file:line), where it was decided (PR / Slack channel+date / style guide line), why, a status (deliberate / partly / drift / undecided) and a question for the tech lead. It also lists the #backend decisions that are not yet merged into the reviewer files. Read it before telling anyone "we do X because…".

## Repo deltas worth knowing

These are where the textbook and Repo differ. Details and page refs are in the source mapping tables.

- **Sync calls to ServiceC:** the book says no sync calls between services, "not even for queries". Repo asks ServiceC over HTTP for every authorization ([AUTHZ-OWNER]). This is a deliberate trade-off. It makes ServiceC a hard runtime dependency, and the resilience advice applies to the ServiceC client.
- **Bus is not RPC:** the book allows async command and reply. Repo forbids request/reply over the bus ([BUS-IS-NOT-RPC]), so Repo is stricter.
- **Shared event library:** the book says don't share one. Repo shares `Repo.Shared.Messaging.Messages`. This conflicts with the book, not with a decision.
- **Outbox:** most Repo publishes are save-then-publish, which the book calls not atomic. Full-row events plus upsert-by-`UpdatedAt` are the safety net. The only real outbox is ServiceD's `MessageSentOutboxDispatcher`.
- **Layers:** the book forbids skipping layers. The Repo team agreed (2025-10-08) that a controller may call a repository when a service adds nothing.
- **Authorization:** the book decides it in-process with policies. In Repo, ServiceC owns authorization and services ask it.
- **Stored procedures:** the book offers them. Repo banned them (2025-09-24).
- **Aggregates:** Repo's entities are table-shaped, with repositories per entity. The book accepts that for CRUD-style services but calls it a smell where rules pile up in services.

## How to use

- From `lift-the-gaze`: when an option needs "how is this usually done", read the matching row above, then the source section. Present the generic way next to Repo's, with the verdict.
- From a review: cite the source and page only to explain *why* a pattern exists. The finding itself must rest on the codebase's rules.
- New source: add `sources/<name>.md` with the same structure. That is a header with licence and page-ref convention, notes per chapter, a Repo mapping table (fits / partly / conflicts), and "questions this source helps answer". Then add its rows to "Where to look".
