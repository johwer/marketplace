# EF Core on Postgres: Repo notes

Short examples for the checklist in `../SKILL.md`. Postgres with Npgsql, not SQL Server, so a few generic tips don't apply (they are marked).

## Reads

```csharp
// Read-only list for a screen: no tracking, only the columns the DTO needs
var rows = await context.ServiceAs
    .AsNoTracking()
    .Where(a => a.CompanyId == companyId && a.StartDate >= from)
    .Select(a => new ServiceAListItem(a.Id, a.UserId, a.StartDate, a.EndDate))
    .ToListAsync(ct);
```

- Tracking costs memory and a snapshot per entity. Leave it on only when the same context will save the entity.
- A projection is also safer: no navigation property leaks into a DTO by accident.

```csharp
// Two collection includes: split so rows are not multiplied
var company = await context.Companies
    .Include(c => c.Departments)
    .Include(c => c.ServiceContracts)
    .AsSplitQuery()
    .SingleOrDefaultAsync(c => c.Id == id, ct);
```

- Single query with two collections returns departments × contracts rows. `AsSplitQuery` runs one query per collection (#backend 2023-10-20).
- Split queries are not one snapshot. If the data changes between them, you can see a mix. That is fine for screens and wrong for a calculation that must be consistent; use a transaction there.

N+1, the common Repo shape:

```csharp
// Wrong: one ServiceC call per user
foreach (var user in users)
    if (await authorizationAdapter.CanDoActionOnUser(token, action, user.Id)) result.Add(user);

// Right: one batched call (e.g. POST authorization/users), then filter in memory
```

- **Filtering early:** call `Where` before `ToListAsync`. A `Where` after materialising runs in memory over every row.
- **`Contains` with many ids (SQL Server tip doesn't apply):** Npgsql sends `ids.Contains(x.Id)` as `x.Id = ANY(@ids)` with one array parameter. No giant `IN` list and no plan-cache explosion. Chunking is not needed for that reason. Still ask why the caller holds thousands of ids.
- **String concatenation in a `Where`** can't use an index. For search, use `EF.Functions.ILike` on an indexed column, or a trigram index if the search is contains-style. Measure first (`backend-performance`).
- **Compiled queries:** rarely worth it here. Only on a measured hot path.

## Writes

```csharp
// One operation, one commit, owned by the service
var service-a = await service-aRepository.GetTracked(id, ct);
service-a.EndDate = request.EndDate;
service-a.UpdatedAt = timeProvider.GetUtcNow().UtcDateTime;
await service-aRepository.SaveChangesAsync(ct);
await publisher.PublishServiceAUpdated(service-a);
```

- New repositories expose `SaveChangesAsync` (or the service holds the context) and don't commit inside `Add`/`Update` methods ([UNIT-OF-WORK]).
- Publish after the commit, awaited ([PUBLISH-AFTER-COMMIT], [UNAWAITED-PUBLISH]).

Set-based change:

```csharp
await context.Notifications
    .Where(n => n.CompanyId == companyId && n.Type == type)
    .ExecuteUpdateAsync(s => s
        .SetProperty(n => n.Enabled, false)
        .SetProperty(n => n.UpdatedAt, now), ct);
```

- Runs one `UPDATE` immediately, without the change tracker.
- It does **not** check the `UpdatedAt` concurrency token and does **not** stamp `UpdatedAt` for you.
- Tracked entities already loaded in the same context keep their old values.
- Events: nothing is published for the changed rows. If consumers keep replicas, publish per row or don't use it.

Explicit transaction, when two commits must stand or fall together:

```csharp
await using var tx = await context.Database.BeginTransactionAsync(ct);
// ... SaveChangesAsync, ExecuteUpdateAsync, pg_advisory_xact_lock
await tx.CommitAsync(ct);
```

- Disposing without commit rolls back. No `catch { Rollback; throw; }` is needed.
- Don't call another service over HTTP inside the transaction. It holds locks for the length of a network call, and a rollback can't undo the remote side.

## Concurrency

- **Token:** `UpdatedAt` configured with `IsConcurrencyToken()` (owl 2025-10-02, ghost 2026-04-01). EF adds `AND updated_at = @original` to the `UPDATE` and throws `DbUpdateConcurrencyException` when someone else wrote first.
- **SQL Server tip doesn't apply:** `[Timestamp] byte[] RowVersion` is SQL Server's `rowversion`. The Npgsql equivalent is the `xmin` system column. Repo has decided on `UpdatedAt`, so use neither without a decision.
- **On conflict:** return 409 to a user request ([CONFLICT-STATUS]). Retry only in a handler where the event is a full row and the newer `UpdatedAt` wins anyway.
- **Serialise a create-or-update race** with `pg_advisory_xact_lock(hashtext(key))` inside the transaction (see `ServiceA.Domain/Repository/UserRepository.cs:154`). The lock is released at commit or rollback.

## Connection and context setup

- `AddDbContext` per service. No `AddDbContextPool` and no `EnableRetryOnFailure` anywhere today. Both are reasonable, but neither is decided, so they are not for a feature PR.
- `EnableSensitiveDataLogging` only in Development. It writes parameter values (personal data) to the logs ([LOG-PII-BOUNDARY]).

## Testing EF code

- InMemory can't see translation errors, `ILike`, JSONB, unique constraints or transactions ([INMEMORY-BLINDSPOT]).
- Where a query's translation is the risk, one integration test on real Postgres (owl, #3420). Otherwise keep integration tests sparse ([INTEGRATION-TEST-SPARSITY]).
