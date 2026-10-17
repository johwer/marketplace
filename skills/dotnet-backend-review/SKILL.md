---
name: dotnet-backend-review
description: Repo-aligned .NET review checklist for the gap other skills don't cover — EF Core query and write hygiene (tracking, projections, N+1, split queries, ExecuteUpdate, transactions, concurrency tokens), async and CancellationToken, typed configuration (IOptions, ValidateOnStart), DI lifetimes, Quartz scheduled jobs, soft-delete filtering, and a few architecture boundary checks. Every item is checked against Repo's standing decisions, and textbook advice Repo has declined (Result<T>, MediatR, AutoMapper, Dapper-first, stored procedures, aggressive caching, the 4-project layout) is listed so it is never recommended. Use when reviewing or writing C# in services/ or shared/, when someone asks "is this EF query OK", "should this be AsNoTracking / ExecuteUpdate / a transaction", "IOptions or IOptionsSnapshot", "is this lifetime right", or from lift-the-gaze once the layer is chosen.
user_invocable: true
---

# .NET Backend Review (Repo)

A checklist for C# in `services/` and `shared/`. It covers what the other backend skills leave out. It never overrides a Repo decision.

## Precedence

1. **Standing decisions:** `~/.claude/commands/ghost-review.md` and `owl-review.md` (tags in `[BRACKETS]`).
2. **Repo docs:** `docs/CODING_STYLE_BACKEND.md`, `API_CONVENTIONS.md`, `TESTING_GUIDELINES_BACKEND.md`.
3. **This checklist**, then generic references (`dotnet-architecture-reference`).

If an item here disagrees with 1 or 2, 1 or 2 wins, and the item is a bug in this skill. Fix it.

## What lives elsewhere (don't repeat it here)

| Topic | Skill |
|---|---|
| Naming, file layout, DTO mapping, JSONB, seeds, enum migrations, Rebus basics, the four security rules | `backend-conventions` |
| Security ordering, ServiceC/RBAC, tenancy | repo skill `security-review`, ghost [AUTH-ORDER] [MULTI-TENANCY] |
| Idempotency, abstraction depth | repo skill `quality-review` |
| Event shape, outbox, redelivery, multi-pod workers | `owl-review` |
| Query plans, indexes, load | `backend-performance` |
| Which layer, which rung | `lift-the-gaze` |
| Why the textbook does it differently | `dotnet-architecture-reference/repo-vs-textbook.md` |

## How to run it

1. Read the diff, plus the real call sites of anything it changes (workers and handlers too).
2. Walk the sections below. Only the ones the diff touches.
3. Report each finding as:
   ```
   [AREA] file:line — what is wrong
   Why: <the Repo rule + source, or the runtime effect>
   Fix: <the smallest change>
   ```
   No source and no runtime effect, no finding. "The textbook says" alone is not a finding.
4. Severity: data loss, wrong data or a crash is **must-fix**. Performance on a hot path is **should-fix**. The rest is **nit**, and nits are optional ([COMMENT-NOISE]).

---

## 1. EF Core reads

Details and examples: `references/ef-core.md`.

- **Read-only query → `AsNoTracking()`.** No Repo context sets NoTracking as the default, so a read that never saves pays for tracking. 76 files already do it.
- **Shape the result in SQL.** `Select` into the DTO or a projection when the caller needs a few columns. Don't load whole entities with their `Include`s to read two fields.
- **N+1:** a repository or `CanDoAction` call inside a loop over a list. Batch it ([BATCH-DB], must-fix in ghost).
- **Many `Include`s → `AsSplitQuery()`** (#backend 2023-10-20). Without it, two collection includes multiply rows.
- **Filter before you materialise.** `ToList()` / `ToListAsync()` and then `Where` filters in memory. So does a `Where` on something EF can't translate (EF throws or, in older code, evaluates client-side).
- **A large `Contains(ids)`:** Npgsql sends it as one array parameter (`= ANY(@p)`), so it doesn't blow up like SQL Server's `IN` list. Thousands of ids is still a smell: often the filter belongs in a join on a replica table.
- **InMemory provider won't catch these.** Translation, `ILike`, JSONB and constraint bugs only show on Postgres ([INMEMORY-BLINDSPOT]). One real-Postgres test where translation is at risk.
- **Soft delete is filtered by hand.** 16 entity models have `DeletedAt`, and no context uses `HasQueryFilter`, so about 63 queries filter `DeletedAt == null` themselves. A new query on such a table must filter too, or say why it wants deleted rows (data erasure, audit). Missing it shows deleted data. Whether a delete should be soft at all is owl [DELETE-SEMANTICS].
- **Heavy SQL with Dapper is fine** (agreed 2026-02-24). Inline SQL in the repository, never a stored procedure ([NO-STORED-PROC]).

## 2. EF Core writes and transactions

- **One commit per operation.** New code calls `SaveChangesAsync` once, from the service, not once per repository call ([UNIT-OF-WORK], [VALIDATE-BEFORE-COMMIT]). Existing repositories that commit inside (≈85 files) are drift, not something to copy. Don't rewrite them in an unrelated PR ([PR-SCOPE]).
- **Validate, then write.** No half-saved state on a 400.
- **Several commits that must succeed together → `BeginTransactionAsync`** (32 files do it). Or one `SaveChanges`. Not two saves and a hope.
- **Publish after commit** ([PUBLISH-AFTER-COMMIT]), and await the publish ([UNAWAITED-PUBLISH]). The outbox is only for critical transitions (`CODING_STYLE_BACKEND.md` "Transactional Outbox").
- **Upserts: no `SetValues()` on entities with immutable fields** ([SETVALUES-IMMUTABLE]). It overwrites `InsertedAt`, `UserId` and the rest.
- **`ExecuteUpdateAsync` / `ExecuteDeleteAsync`** for set-based changes (29 files). Know what you skip: no change tracker, no concurrency token check, and `UpdatedAt` is not set unless you `SetProperty` it. Repo has no interceptor that stamps it. Inside an explicit transaction it joins it; outside it commits on its own.
- **Concurrency token: `UpdatedAt` with `IsConcurrencyToken()`**, so the check is in the `UPDATE … WHERE`, not an `if` in C# (owl 2025-10-02). Never two tokens (ghost 2026-04-01). Not SQL Server `rowversion` and not `xmin` unless decided.
- **Serialising a race:** `pg_advisory_xact_lock(hashtext(...))` inside the transaction (`ServiceA.Domain/Repository/UserRepository.cs:154`, `ServiceB…/TemplateRepository.cs:215`), or `PostgresDistributedLockService` across pods. Scope the lock to the smallest key ([CONCURRENCY-SCOPE]).
- **Child Guids set in C# need `ValueGeneratedNever()`**, or EF treats new rows as Modified and throws a concurrency error (ghost 2026-04-02).
- **Schema changes:** generated migrations only ([MIGRATION-BY-HAND]). Renaming an entity keeps the table name so EF emits a rename (#backend 2024-09-10). Expand, then contract ([EXPAND-CONTRACT]), and the migration tooling must keep up ([MIGRATOR-PARITY]).

## 3. Async and cancellation

- **Async all the way.** No `.Result`, `.Wait()` or `GetAwaiter().GetResult()` (none on `main` today, keep it that way). No `async void`.
- **Pass the `CancellationToken`** from the controller action down to EF and `HttpClient` (`CODING_STYLE_BACKEND.md:517`). A long query on an aborted request keeps a connection busy.
- **Don't `Task.WhenAll` over one `DbContext`.** A context is not thread-safe, and two queries in parallel on it throw. Parallel is fine for independent HTTP calls. The generic "use WhenAll" advice is a trap here.
- **No `Task.Run` around code that is already async.**
- **Background work that outlives the request** creates its own scope. Never capture a scoped service in a continuation or a field ([SCOPE-DISPOSAL], must-fix).

## 4. Configuration

- **Typed options:** a class bound with `services.AddOptions<T>().Bind(config.GetSection("X"))`. Add `.ValidateDataAnnotations().ValidateOnStart()` when a missing value would fail later at runtime (as in `ServiceC.API/Program.cs:58`). A bad config should stop the pod, not the first request.
- **Lifetimes:** `IOptions<T>` is read once (fine in singletons). `IOptionsSnapshot<T>` is per request (scoped, so never inject it into a singleton). `IOptionsMonitor<T>` notices changes in a singleton. Most Repo config never changes at runtime, so `IOptions<T>` is the default.
- **No raw `configuration["X:Y"]` deep in services** when a typed options class exists or would do. Read at the edge, inject the typed value.
- **Secrets and environment:** follow [SECRETS-CONFIG]: sensitive values in AWS Secrets Manager, the rest in appsettings. APIs read `ASPNETCORE_ENVIRONMENT`, workers `DOTNET_ENVIRONMENT` (#backend 2026-09-30).
- **Not a feature switch.** A config bool that turns a customer feature on or off is a contract or data decision ([CONTRACT-IS-THE-SWITCH], [PRODUCT-IS-DATA]).

## 5. DI and HTTP clients

- **Lifetimes:** a singleton must not depend on a scoped service (captive dependency). `DbContext` and repositories are scoped.
- **`IHttpClientFactory` / `AddHttpClient`,** never `new HttpClient()` (none on `main`).
- **Resilience:** Repo has no Polly or `Http.Resilience` today, and there is no decision either way (`repo-vs-textbook.md` "HTTP resilience"). Don't add it inside a feature PR. Raise it as a question if the diff adds a new hot cross-service call ([NECESSITY]).
- **Timeouts:** a new outbound client sets one. The default of 100 s holds a request thread far too long.

## 6. Scheduled jobs (Quartz)

Quartz runs 19 `IJob`s in five ServiceA and ServiceC workers, with the in-memory store (no `UsePersistentStore`, no clustering). Every pod schedules every job. Today the worker deployments checked (deviant engine, callback engine, export, quarantine) run `replicas: 1`, and the engines take `PostgresDistributedLockService` locks in their services rather than in the job.

- **More than one pod?** If the diff raises `replicas` or adds a job to a worker with more than one, each pod runs it. Guard the work with a distributed lock or a claim row, or keep `replicas: 1` on purpose. Note that this conflicts with "at least 2 replicas" for workers (owl 2025-04-07, [CONCURRENCY-SCOPE]), so say which one wins. Open question to the tech lead in `dotnet-architecture-reference/repo-vs-textbook.md`.
- **Overlap on one pod:** a job that can run longer than its interval needs `[DisallowConcurrentExecution]` (3 of the 19 have it).
- **Re-run safe:** a job can fire again after a crash or a deploy. Each item it handles must be idempotent: a claim, an "already sent" marker in the same transaction, or upsert ([REDELIVERY-SAFETY], [EVENT-IDEMPOTENCY]).
- **Scope per run:** resolve `DbContext` and repositories from a scope created inside `Execute`, not from the job's constructor if the job is a singleton ([SCOPE-DISPOSAL]).
- **Cancellation:** pass `context.CancellationToken` down, so a shutdown stops the run instead of being killed mid-write.
- **Batches, not everything:** load work in pages and commit per batch, so one bad row does not roll back the run, and log the row that failed ([FAIL-LOUD]).
- **Time:** cron in UTC or an explicit time zone, and "today" from `TimeProvider`, not `DateTime.Now`.

## 7. Architecture boundaries (adapted from clean architecture)

Six rules worth keeping, in Repo's terms. The rest of the book's strictness is listed in section 8.

1. **Dependencies point inward.** `*.Domain` never references `*.API`, HTTP types, DTOs or `ApiResponse`. A project reference to another service's project is "Illegal!" ([CROSS-SERVICE], 2025-12-17).
2. **Thin controller.** Route, token, shape validation, ServiceC check, one service call. Business `if`s go down a layer. A controller may call a repository when a service would only pass through (team agreement 2025-10-08).
3. **The service owns the transaction.** One operation, one commit, decided where the use case is (ties to section 2).
4. **A boundary costs something.** Add an interface, a layer or a project only when it pays for itself now. "Something new needs taste, judgment and consensus. Something existing is just to go hard" (2026-10-16, [NECESSITY], [SPECULATIVE-GENERALITY]).
5. **Anti-corruption at the legacy edge.** Legacy and SignedIn shapes are translated where they enter (the sync/port code), not spread through Nova's services. A port keeps legacy behaviour unless a decision says otherwise.
6. **A rule has one home.** If a worker and an API both need it, it lives in `*.Domain` (a Policy or a shared reader), not copied ([ONE-HOME-FOR-A-RULE]).

## 8. Textbook advice Repo has declined

Never recommend these. If someone asks, explain with the source.

| Advice | Repo | Source |
|---|---|---|
| Return `Result<T>` from services, map to HTTP in one place | Services return `ApiResponse<T>` | `CODING_STYLE_BACKEND.md:521`, owl [RESPONSE-CONTRACT] |
| MediatR, command/query handlers, pipelines | Not used; plain services | [REUSE-FIRST], #backend 2025-08-18 |
| CQRS writes through a worker | Rejected, "one of the biggest painpoints" | #backend 2025-08-18, [BUS-IS-NOT-RPC] |
| AutoMapper | Static `MapFromDomain` / `MapToDto` | `CODING_STYLE_BACKEND.md:480` |
| Prefer Dapper for reads | EF by default, Dapper for heavy SQL | #dream-team 2026-02-24 |
| Stored procedures | Banned | [NO-STORED-PROC], 2025-09-24 |
| Cache aggressively | Only with invalidation on change, measured first | [CACHE-INVALIDATION] |
| Domain / Application / Infrastructure / Api projects | `*.API` + `*.Domain` (Domain holds DbContext and migrations) | `repo-vs-textbook.md`, undecided but existing |
| Ports, presenters, logging behind a domain interface | Not used; `ILogger<T>` injected directly | [NECESSITY] |
| `AddDbContextPool`, `EnableRetryOnFailure` | Not used anywhere | No decision; don't add in a feature PR |
| FluentValidation | Hand-written checks at the controller | `CODING_STYLE_BACKEND.md:89` (the `:103` mention is unused) |

## Output

Group findings by severity. End with one line: what the diff does well on the points above, if anything. Don't post anywhere. Hand PR comments to the user, or to `review-pr`.

## Sources

Rewritten in our own words from two MIT-licensed marketplace skills, `dotnet-backend-patterns` and `clean-architecture`, then checked line by line against Repo's code and decisions. The notices are in `NOTICE.md`. The originals are staged, unloaded, in `~/.claude/skills/imported/`.
