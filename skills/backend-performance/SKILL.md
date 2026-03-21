---
name: backend-performance
description: Backend/.NET performance optimization — EF Core queries, API response times, caching, database tuning, memory profiling
---

## Performance Targets

| Metric | Target | Action threshold |
|--------|--------|-----------------|
| **API response (p95)** | < 200ms | > 500ms investigate |
| **Database query** | < 50ms | > 200ms optimize |
| **TTFB** | < 600ms | > 1.3s critical |
| **Memory per request** | < 5MB | > 20MB profile |

## Performance Checklist

### Database (highest impact)

**Query Optimization**
- [ ] No N+1 queries — use `.Include()` for related entities, check EF Core logs
- [ ] Avoid `SELECT *` — use `.Select()` projections for read queries
- [ ] Use `.AsNoTracking()` for read-only queries (30-50% faster)
- [ ] Pagination on all list endpoints — never return unbounded results
- [ ] Indexes on all `WHERE`, `ORDER BY`, and `JOIN` columns
- [ ] Monitor slow queries — log queries > 200ms

**EF Core Patterns**
- [ ] DbContext is Scoped (one per request), never Singleton
- [ ] Use compiled queries for hot paths: `EF.CompileQuery()`
- [ ] Split queries for multi-collection includes: `.AsSplitQuery()`
- [ ] Avoid lazy loading in APIs — explicit `.Include()` only
- [ ] Batch operations — `ExecuteUpdate()` / `ExecuteDelete()` for bulk
- [ ] Connection pooling configured (default in .NET, verify pool size)

**Database Maintenance**
- [ ] Index fragmentation monitored
- [ ] ServiceE updated regularly
- [ ] Old data archived or cleaned up
- [ ] Query plans reviewed for expensive operations

### API Response

**Payload**
- [ ] Response compression enabled (GZIP/Brotli middleware)
- [ ] Minimize payload — return only needed fields
- [ ] Pagination with consistent pattern (offset/limit or cursor)
- [ ] Streaming for large responses (`IAsyncEnumerable<T>`)

**Caching**
- [ ] HTTP cache headers (Cache-Control, ETag) for stable data
- [ ] In-memory cache (`IMemoryCache`) for hot data with TTL
- [ ] Distributed cache (Redis) for shared state across instances
- [ ] Cache-aside pattern: check cache → miss → fetch → store → return
- [ ] Cache invalidation on writes (tag-based or key-based)

**Background Processing**
- [ ] Long operations → background jobs (not in request pipeline)
- [ ] Message queues for cross-service communication
- [ ] Fire-and-forget with proper error handling

### Code Optimization

**Async/Await**
- [ ] All I/O operations are async (database, HTTP, file)
- [ ] No `.Result` or `.Wait()` — causes thread pool starvation
- [ ] `ConfigureAwait(false)` in library code
- [ ] Use `ValueTask<T>` for hot paths that often complete synchronously

**Memory**
- [ ] Use `Span<T>` / `Memory<T>` for buffer operations
- [ ] Avoid large object heap (LOH) allocations — objects > 85KB
- [ ] `ArrayPool<T>.Shared` for temporary arrays
- [ ] `StringBuilder` for string concatenation in loops
- [ ] Avoid closures in hot paths (lambda captures)

**Serialization**
- [ ] System.Text.Json only (not Newtonsoft) — 2-3x faster
- [ ] Source-generated serializers for hot paths: `[JsonSerializable]`
- [ ] Minimal property sets — `[JsonIgnore]` unused properties

### Network & Infrastructure

- [ ] Connection timeouts and retries configured
- [ ] Circuit breaker for external service calls (Polly)
- [ ] HTTP keep-alive enabled (default in HttpClient)
- [ ] Use `IHttpClientFactory` — never `new HttpClient()` per request
- [ ] Rate limiting on public endpoints
- [ ] Health check endpoint for load balancer

## .NET Performance Antipatterns

```csharp
// BAD: N+1 — fetches each order separately
var users = await db.Users.ToListAsync();
foreach (var user in users)
    user.Orders = await db.Orders.Where(o => o.UserId == user.Id).ToListAsync();

// GOOD: Single query with Include
var users = await db.Users
    .Include(u => u.Orders)
    .AsNoTracking()
    .ToListAsync();
```

```csharp
// BAD: Loads entire table into memory
var allUsers = await db.Users.ToListAsync();
return allUsers.Where(u => u.IsActive).Take(10);

// GOOD: Filter and page in database
var users = await db.Users
    .Where(u => u.IsActive)
    .OrderBy(u => u.Name)
    .Skip(offset).Take(limit)
    .AsNoTracking()
    .ToListAsync();
```

```csharp
// BAD: Thread pool starvation
var result = httpClient.GetAsync(url).Result;

// GOOD: Async all the way
var result = await httpClient.GetAsync(url);
```

```csharp
// BAD: New HttpClient per request (socket exhaustion)
using var client = new HttpClient();
var response = await client.GetAsync(url);

// GOOD: IHttpClientFactory (pooled, managed)
public MyService(IHttpClientFactory factory)
{
    _client = factory.CreateClient("ServiceName");
}
```

## Profiling Tools

| Tool | Purpose | Usage |
|------|---------|-------|
| **EF Core logging** | Query analysis | `.LogTo(Console.WriteLine, LogLevel.Information)` |
| **MiniProfiler** | Per-request profiling | NuGet: MiniProfiler.AspNetCore |
| **BenchmarkDotNet** | Micro-benchmarks | `[Benchmark]` attribute on methods |
| **dotnet-counters** | Runtime metrics | `dotnet-counters monitor` |
| **dotnet-trace** | CPU profiling | `dotnet-trace collect` |
| **dotnet-dump** | Memory analysis | `dotnet-dump analyze` |

## Recommended External Skills

```bash
# Official Microsoft .NET skills — performance investigations, debugging
# From: github.com/dotnet/skills

# Aaronontheweb dotnet-skills — 30 skills + 5 agents (EF Core, concurrency, perf)
/plugin marketplace add Aaronontheweb/dotnet-skills

# wshaddix dotnet-skills — 167 skills (N+1 detection, query optimization, database-performance)
# From: github.com/wshaddix/dotnet-skills
```
