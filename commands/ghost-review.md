---
context: fork
---

# Ghost Review — Pre-emptive Backend Code Review

Simulate cachpachios' review style against a PR or ticket before he sees it. Flags must-fix issues and surfaces the clarifying questions he would ask, so they're resolved before the review cycle.

$ARGUMENTS

## Who is cachpachios?

Cachpachios is a senior backend reviewer who:
- Asks architecture-first questions before accepting a design
- Expects developers to apply architectural judgment to the ticket itself: a mechanism relayed from product/customer (even "TT wants X") is a *suggestion, not a spec* — push back and model it the way the system actually works ("my expectation is that we apply judgment about that before implementation")
- Flags security issues (auth ordering, multi-tenancy, privilege escalation) as must-fix
- Leaves clarifying questions when semantics are ambiguous — he won't approve until they're answered
- Is consistent about patterns he's flagged before: he will ask again
- Has a 0% resolution rate on "missing integration test" flags (0/9 in scraped history) — the team tends not to add them, so he keeps asking
- Prefers code that **fails loud** (throw) over silent defaulting, null-coalescing fallbacks, `continue`, or returning stale data on failure
- Pushes for **enums/domain constants** over hardcoded strings, and dislikes fully-qualified namespaces (FQDN) in code

His review style: precise, code-specific, not generic. He cites the exact file and line pattern. He doesn't nitpick style (linters handle that) but he does care about naming when it violates REST or DTO conventions.

> **Data backing these patterns** (from `pr-learnings.json`, scraped review history): **1,103 review comments** by cachpachios across ~590 PRs he reviewed (106 must-fix). Categories: pattern (118), architecture (109), naming (59), api-contract (58), types (51), missing-test (51), error-handling (47), security (40, highest must-fix rate), performance (17), plus many clarifying questions. His must-fix verdicts concentrate in **security, error-handling, architecture, and EF/persistence modeling**. He frequently flags: layering/Unit-of-Work violations, AWS credential/region hardcoding, token-authority & header spoofing, catch-and-log-only, build warnings, commented-out code, and tests that don't assert real logic.

## Input

Parse `$ARGUMENTS` to determine mode:

- **PR number** (e.g. `2581`) — Review a specific PR
- **No arguments** — Auto-detect PR from current branch: `gh pr view --json number`
- **Ticket ID** (e.g. `NOVA-2547`) — Review a ticket design (pre-implementation questions only)

## Config

Read `~/.claude/dtf-config.json` if it exists. Use `repo` field for the GitHub repo slug (fallback: `RepoAB/Repo`).

## Mode 1: PR Review

### Step 1 — Fetch PR data

```bash
gh pr view <PR> --repo <REPO> --json number,title,headRefName,body,files,author
gh api repos/<REPO>/pulls/<PR>/files   # full file list with patches
```

Skip non-backend files for this review: ignore `*.tsx`, `*.ts`, `*.snap`, `*.json`, `*.md`, `*.sql` seed files, `*.Designer.cs`, `*ModelSnapshot.cs`.

Focus on: `*Controller.cs`, `*Repository.cs`, `*Service.cs`, `*Handler.cs`, `*Worker.cs`, `*.Domain/**`, `*Mapper.cs`, `*Request.cs`, `*Response.cs`, `*.cs` in shared/

### Step 2 — PR description pre-emption scan

Extract what the PR description explicitly acknowledges. These are already "on the table" — cachpachios may still comment but the team has a prepared answer. List them:

```
### Already pre-empted in description:
- [list of acknowledged decisions]
```

### Step 3 — Apply the checklist

Run each check below against the actual diff/patches. Only flag a check if the code *actually shows the pattern* — not hypothetically. Cite exact file and line context from the patch.

---

#### MUST-FIX patterns (cachpachios blocks approval on these)

**[AUTH-ORDER] Permission check after data fetch**
Look for controller methods that:
1. Call a repository `GetById` / `GetByAsync` / `FindAsync` BEFORE calling `CanDoAction` / `HasPermission` / `_authorizationAdapter`
2. Return 404 if not found, THEN 403 if no permission

Why this is flagged: an unauthorized caller can probe existence — unknown ID → 404, known ID → 403. Fix: check permission first, return 403 regardless of existence.

Pattern to search: in controller method bodies, find `GetByIdAsync` or `FindAsync` call followed (without a permission check first) by a null check, THEN a permission call.

**[PRIVILEGE-SCOPE] UserPermission used for company-wide action**
Look for controller endpoints that perform company-wide operations (affect all users in a company, create/delete roles, manage assignments) but check `UserAction.*` instead of `CompanyPermission.*` / `CompanyAction.*`.

Company-wide = role management, bulk operations, company settings, subscription management.

Recurring concrete cases he has flagged in `TTPermissionsMappings.cs` / `ActionsMap.cs`:
- `UserEdit` (or a single user-level action) granting too much — e.g. allowing SSN update. User-level edit must not also authorize sensitive operations.
- Scoping *company* permissions based on a *user-level* permission — he calls this a security violation outright.
- Creating/editing roles gated behind user-level permissions — role management is company-scoped.
If a PR touches permission mappings, scrutinize whether each granted action matches the scope (user vs company) of what it actually authorizes.

**[MULTI-TENANCY] Missing cross-tenant validation**
Look for:
- Service/handler methods that accept `companyId` from request body/params without validating it belongs to the `customerId` from the JWT
- Event handlers that use `roleData.CompanyId` or similar payload fields instead of `message.CompanyId`
- Repository queries that filter by `companyId` without also filtering by `customerId`
- Role-assignment / entity-binding code that does not validate the **roles (or referenced entities) actually belong to the validated company** — e.g. assigning a role by ID without confirming that role is owned by the caller's company (flagged as a "large security issue" in `RoleAssignmentRepository.cs`)
- Endpoints missing **customer scoping** needed to support cross-tenant users (e.g. `UserWidgetController`)

**[S2S-VS-USER-API] User-facing API reused as service-to-service**
Look for a user-facing controller/endpoint (or `AuthorizationAdapter` built for user-context auth) being called or reused as a service-to-service (S2S) path. The authorization models differ — user APIs assume a JWT user context; S2S has none. Reusing one for the other violates the Repo bus-driven pattern. Flag if a user-auth endpoint is being consumed internally as if it were an S2S contract.

**[AUTHORIZED-FEATURES-MISUSE] Field added to `authorizedFeatures` for an external/non-FE consumer**
`customer/{id}/authorizedFeatures` models **Repo's own frontend viewport** (which UI/nav a signed-in user sees). Do NOT add a boolean there for an external system (Seru/Leo, other services) or for a permission the Repo FE doesn't consume — it's noise and doesn't scale. External systems read a user's grants via the existing `authorization/.../action/{action}` endpoints. Flag any new `authorizedFeatures` field whose only consumer is external or non-UI. (NOVA-3183.)

**[PERMISSION-PLACEMENT] Permission modeled at the wrong scope or filed under an unrelated contract**
Two checks. (1) A company-level capability must be a `CompanyPermission`/`CompanyAction`, not `UserPermission`/`UserAction` — mirror the closest existing feature (e.g. `TTViewInsightsHub` → `InsightsHubRead` for analytics). (2) Don't gate a permission under a `ServiceContractType` it merely *resembles by name* (e.g. parking a "Reporting" permission under `ServiceE`) — `ServiceContractType` reflects the **contract that entitles** it. If it's universal to a retailer, put it in the `AlwaysOn` baseline instead; only use a contract entry if a real contract gates it. Note `ServicePermissionMap.Compose` is a test-only consistency layer (no live callers) — the live grant path is `ProductMap`. (NOVA-3183.)

**[UNIT-OF-WORK] SaveChangesAsync inside a repository, or called multiple times**
Look for `SaveChangesAsync()` / `SaveChanges()` called inside a `*Repository.cs` method. Repositories must not commit — the Unit of Work boundary belongs at the service/handler layer. He blocks on this. Also flag **more than one `SaveChangesAsync` in a single operation** ("please do not do two SaveChangesAsync here — ideally call it once for the entire update") — multiple saves break atomicity.

**[SCOPE-DISPOSAL] Disposed DI scope or service used after disposal**
Look for a scoped service or `IServiceScope` captured and then used after the `using`/scope has ended (e.g. stored on a field, passed to a continuation, or awaited after disposal). Causes a resource leak / `ObjectDisposedException`. Also watch for per-item DB calls inside a loop — he flags N+1 round-trips as must-fix when the volume is unbounded.

**[SETVALUES-IMMUTABLE] EF Core SetValues() on audited entities**
Look for `entry.CurrentValues.SetValues(...)` or `dbSet.SetValues(...)` on entities that have fields like `InsertedAt`, `CreatedAt`, `UserId`, `CreatedBy`. SetValues() overwrites everything including audit fields.

**[DEPLOY-PIPELINE] New containerized service/worker without _deploy.yml update**
Look for new `*.Worker` or `*.Api` projects (new `.csproj` files, new `Dockerfile`) that aren't matched by a corresponding image push step in `.github/workflows/_deploy.yml`. Only flag if there's a new project being added.

**[HTML-ENCODING] Unencoded user-controlled values in email templates**
Look for string interpolation or `Replace()` calls in email template generation where the substituted value comes from user-controlled data (Department name, user name, company name). Flag if `System.Net.WebUtility.HtmlEncode()` is not applied.

**[DTO-NAMING] DTO missing Request/Response suffix**
Look for DTOs returned from or accepted by controllers that don't carry a `Request`/`Response` suffix, or response models reused as request bodies (which forces awkward field assignments). He treats the suffix convention as must-fix, not a nitpick.

**[MIGRATION-BY-HAND] EF migration files edited manually**
Look for hand-edits to generated migration files (`*_Migration.cs`, `*Designer.cs`, `*ModelSnapshot.cs`) instead of regenerating via `dotnet ef migrations remove` + re-add. Also flag data-correction needs that should ship as a migration (e.g. "add a migration to lowercase all existing tokens") rather than being assumed. (Note: a migration-guard hook also warns on this.)

**[EF-MODELING] Incorrect entity / migration modeling**
He is strict about the data model. Flag:
- Migrations with only a PK constraint where a **foreign-key relationship** is missing ("missing FK relationship in migration")
- Columns stored as `int` that represent an enum ("No ints plz! Fix all enums")
- Wrong numeric types (`decimal` where a count should be `int`)
- Missing `ValueGeneratedNever()` / value-generation config on PKs that are assigned, not generated
- Compound-key tables without a **unique index** on the composite key to prevent duplicate rows

**[AWS-CREDS] Hardcoded AWS credentials, secret-key auth, or region**
Flag in `*.tf`, `appsettings*.json`, `docker-compose.yml`, or adapter code:
- Forcing key/secret authentication instead of letting the **AWS credential chain** discover credentials (in EKS the app is granted an integrated ServiceC role — do not add access-key/secret-key config)
- A **hardcoded AWS region** — and note that Polaris is `eu-north-1`; a hardcoded `us-*`/other region is wrong

**[AUTH-SPOOF] Token authority / spoofable headers not locked down**
Security must-fix:
- JWT/OpenID validation that doesn't pin the **Authority/issuer** so only the intended provider's keys validate ("I hope we're damn sure Authority ensures only Microsoft keys are validated — otherwise anyone can spoof us")
- Trusting forwarded headers (`X-Forwarded-For`, etc.) without the edge (CloudFront) stripping/blocking incoming values — flag if forwarded headers are read for auth/IP decisions without an edge guard

**[BUILD-WARNINGS] Compiler warnings left in**
Flag new build warnings (unused usings, obsolete API, nullable warnings). "Fix build warnings — eventually CI will forbid committing with warnings." He treats this as must-fix.

**[NO-COMMENTED-CODE] Commented-out code merged in**
Flag blocks of commented-out code in the diff. "Never merge commented code." He will not approve with it present.

---

#### CLARIFYING QUESTIONS (cachpachios asks before approving)

**[ROUTES] Action-based URL paths**
Look for `[HttpGet("getX")]`, `[HttpPost("createX")]`, `[HttpDelete("deleteX")]`, `[HttpGet("searchX")]` — any route attribute where the path segment is a verb + noun.
Right: `[HttpGet("user/{userId:guid}/documents")]`
Wrong: `[HttpGet("getDocuments")]`
Also flag: camelCase URL path segments (should be kebab-case).

**[UPSERT-PREFS] Upsert on user-preference tables**
Look for `AddOrUpdate`, `CreateOrUpdate`, `ExecuteUpdate` (or `SetProperty`) calls in sync workers, import handlers, or event handlers that write to tables containing user-settable preferences (language, notification settings, opt-in flags). The fix is conditional create: check if exists first, only create if absent.

**[EXCEPTION-FLOW] OperationCanceledException caught broadly**
Look for `catch (OperationCanceledException)` at a scope wider than the specific `await` that uses the cancellation token. The catch should be scoped tightly, not at the method or class level.

**[CROSS-SERVICE] ServiceC-owned concerns edited in ServiceB/ServiceA**
Look for modifications to:
- Permission mappings or `TTPermissionsMappings`
- `MaskSsn` / anonymization logic
- Role definitions
- Subscription logic driven by ServiceC contracts
...when the changes are in `services/ServiceB/` or `services/ServiceA/` rather than `services/ServiceC/`.

**[REPO-PATTERN] Repository method that does no I/O**
Look for repository methods that receive an already-loaded entity and only read/project its properties without any database call (`Task.FromResult(...)` wrapping entity field access). These belong in the controller or a mapper, not the repository layer.

**[VALIDATION-SEMANTICS] Missing server-side validation for conditional requirements**
Look for DTOs where some fields are only required when another field has a specific value (e.g., dates required when a toggle is true, value required when a type is string-valued), but no `[Required]` or guard logic enforces this in the controller or a validator.

**[FEATURE-SCOPE] Backend endpoint wider than feature scope**
If the PR description says the feature is scoped to a specific retailer/tenant (e.g., MH-only) but the backend endpoint has no tenant guard, ask: what prevents other retailers from calling this endpoint? Is the frontend-only gate intentional and sufficient?

**[MISSING-TEST] No integration test for new persistence round-trip**
Look for new `POST`/`PUT`/`DELETE` controller endpoints with no corresponding `IntegrationTests` project test that exercises the full round-trip: HTTP call → database write → verification. Unit tests that mock the repository do not count.

Important nuance he repeats: integration tests should test **round-trips and access/permission scenarios**, NOT unit-level logic paths. He explicitly notes that "Claude tends to ALWAYS" write integration tests that are really unit tests, and he asks for them to be removed. So when an agent adds integration tests, check they exercise the HTTP→DB→verify path or permission/access matrix — not branch coverage of a single method. Schema changes with no test touched also draw a "why no test?" question.

He is also strict that tests must **assert real logic, not just pass**: flag mocks/assertions like `It.IsAny<Guid>()`, asserting only that a call happened, or loose matchers that would pass regardless of correctness. "Don't just `IsAny<Guid>`. Please validate your logic in the tests, don't just make the tests pass!" A new endpoint with *no* tests at all is a hard must-fix for him ("makes no sense to not have any tests... please make it a habit").

**[INTEGRATION-TEST-SPARSITY] Too many integration tests where unit tests suffice**
The flip side of MISSING-TEST: cachpachios treats integration tests as **expensive (time/CI budget)** and wants them **sparse** — usually a single happy-path is enough. When a PR adds several integration tests covering scenario/branch variations (e.g. granted→true, not-granted→false, leak-guard→false all as integration tests), flag it: keep at most ONE happy-path integration test and **move the rest to unit tests** (mapping tests, scope-resolution tests, helper-level assertions). His verbatim: "Drop these tests please, i dont think it adds a lot of value, and a integration test its quite expensive (time budget-wise)... What you can do is move it to a unit test though. Future consideration is to always be sparse with integrationtests, mostly a single one testing a 'happy' path is enough." So default new-behavior coverage to unit tests, reserving integration for one round-trip/access-matrix happy path. (Source: NOVA-3183 review.)

**[SEARCH-IS-GET] Search/read endpoint modeled as POST**
Look for new search/list/read endpoints implemented as `[HttpPost]` with a request body. He pushes for `GET` with query parameters instead — it's the more typical endpoint shape, and RTK Query defaults such endpoints to a `query` (cache) rather than a `mutation`. Ask: should this be a GET with query params?

**[FAIL-LOUD] Silent defaulting instead of throwing**
Look for code that swallows an unexpected state instead of surfacing it:
- Null-coalescing to a default (`?? new(...)`, `?? defaultValue`) where the code logically expects the value to never be null
- `continue` / silent skip inside a loop on an unexpected condition
- Returning stale/cached data (or a logged warning) when a fetch fails, instead of throwing
- `catch` that logs and proceeds
- **Catching a generic `Exception` just to log it** — "bad practice to catch generic exceptions just for logging; errors are already logged and a 500 returned." Remove the catch or handle a specific exception.
His preference: throw (or null-coalesce to an exception). Ask whether the silent path is intentional or hiding a bug.

**[NULL-OVER-SENTINEL] Sentinel/default value instead of nullable**
Look for sentinel values standing in for "missing": `Guid.Empty` returned/accepted instead of `Guid?` + `null`, default `0`/`DateTime.MinValue` as "not set", etc. He wants nullable types so service-a is explicit ("Guid.Empty is one of .NET's crimes... return `Guid?` and null if missing, not `Guid.Empty`").

**[CONFLICT-STATUS] Conflict/duplicate cases not handled with proper status**
For create endpoints, ask how conflicts are handled — e.g. duplicate username/email should validate and return **409**, not assume uniqueness or let the DB throw. Also flag assuming a related row exists ("I don't think you can assume AuthInfo exists").

**[ENUM-OVER-STRING] Hardcoded string where a type/enum/constant belongs**
Look for string literals or `string`-typed fields/parameters representing a closed set of values (statuses, types, language codes, property names) that should be an exported enum from the API contract or a domain constant. He repeatedly asks "why is this a string, shouldn't it be an enum/its own type?" — and flags hardcoded language strings that belong in an ServiceC domain constant.

**[BATCH-DB] Per-item database round-trips**
Look for DB calls (`CanDoAction`, `GetByIdAsync`, repository reads) executed once per item in a loop over a collection. He suggests batched operations to collapse multiple round-trips into one. Question intensity scales with how unbounded the collection is (must-fix when unbounded — see SCOPE-DISPOSAL/N+1 above).

**[PAGINATION] Unbounded fetch**
Look for queries that fetch everything (no `Take`/page size, `int.MaxValue` as a limit, "get all" endpoints). He pushes back on `MaxValue` and asks whether the endpoint needs pagination. Flag list/search endpoints returning unbounded result sets.

**[FQDN] Fully-qualified namespaces in code**
Look for fully-qualified type names / namespaces inline in code (e.g. `Some.Long.Namespace.Type`) instead of a `using`. He flags this as unnecessary noise.

**[FRAME-MISMATCH] Frontend reinterprets a value without reading what the backend does with it**
When a frontend change alters how a value is **parsed, compared or serialised** — dates, currency,
IDs, anything with a unit or frame — read the producing backend before accepting the change. Three
greps, and they catch the class of bug a diff-only review cannot see:

1. **Read the producer.** Find the DTO property and the SQL/expression behind it. What type is it
   (`DateTime` vs `DateOnly` vs `string`)? Does one response column come from more than one source?
   A `UNION ALL` can put two different frames in one field, in which case a single parse is wrong
   for half the rows.
2. **Read the comparison.** Find where the backend uses the value in a predicate. A frontend fix
   reasoned from what a stored value *means* is a no-op — or a regression — if the server compares
   it in a different frame (e.g. truncating to `DateTime.UtcNow.Date` while the client brackets a
   local day).
3. **Trace the round-trip.** If the value has both a read and a write path, check that
   read → edit → save with no user change is idempotent. Fixing one side alone silently rewrites
   stored data on save.

Flag as MUST FIX when the PR changes a parse/compare and cites no evidence of the producing type or
the server-side comparison. "It renders correctly now" is not that evidence.

(NOVA-3618: three separate instances in one PR. A dashboard column unioning `inserted_at` with
`planned_at` meant one parse broke whichever half it did not suit; a pause window rewritten to
bracket local days was inert because the repository compares against `UtcNow.Date`, and skipped a
day at negative offsets; and a timezone guard asserted a wire shape the DTO never sends. All three
were invisible to tsc, eslint, 2000 unit tests, real-browser verification in two zones, and a
diff-scoped pre-emptive review — because every one of them lived in code adjacent to the diff
rather than in it.)

---

### Step 4 — Format findings

Output in cachpachios' style: code-specific, no preamble, grouped by severity.

```
## Ghost Review — PR #<N>: <title>

### Already handled in PR description
<bullet list of pre-empted items>

---

### Must Fix

**[AUTH-ORDER]** `UserController.cs` — `GetFirstDayCertificateRequirement`
The user is fetched before the permission check. An unauthenticated caller can probe user existence: unknown `userId` → 404, known `userId` → 403. Permission should be checked first and return 403 regardless.

...

---

### Clarifying Questions

**[ROUTES]** `UserController.cs`
Route `{userId:guid}/firstDayCertificateRequirement` uses camelCase path segment. Convention is kebab-case: `first-day-certificate-requirement`. Is this intentional?

**[FEATURE-SCOPE]** `UserController.cs`
The PR description says this is MH-only but the endpoint has no tenant guard. What prevents non-MH retailers from calling PUT? Is the frontend `skip: !isRepo` the only gate?

...

---

### Not flagged
<patterns that were checked but not present in this PR>
```

---

## Mode 2: Ticket Pre-Implementation Review

Use this when the user provides a ticket ID instead of a PR number.

### Step 1 — Fetch the ticket

```bash
acli jira workitem get <TICKET_ID>
```

### Step 2 — Ask the architecture questions cachpachios would ask

Before any implementation starts, surface the questions he would ask in review — so they're answered up front:

**Authorization design:**
- Which permission gates this endpoint? `UserAction.*` or `CompanyPermission.*`? Is the action user-scoped or company-scoped?
- Does the GET check permissions before fetching, or after?

**Multi-tenancy:**
- Does any input include a `companyId` from the caller? If so, is it validated against the JWT's `customerId`?

**API contract:**
- Are the route paths resource-based (noun paths, no verb segments)?
- Are path segments kebab-case?
- Is any search/read endpoint a POST? Should it be a GET with query params (RTK `query`)?
- Do request/response DTOs carry the `Request`/`Response` suffix, and are response models kept separate from request models?
- Do closed-set values use exported enums/domain constants rather than raw strings?

**Persistence:**
- Is any write path an upsert over user-settable data? If yes, should it be conditional create?
- Does the new endpoint have a full round-trip integration test planned? (Round-trip / access scenarios — not unit-logic-path tests.)
- Does any repository method commit (`SaveChangesAsync`) — i.e. is the Unit of Work boundary in the wrong layer?
- Are there per-item DB round-trips that should be batched?

**Error handling:**
- On unexpected/null state, does the design throw (fail loud) or silently default / return stale data?

**Scope:**
- If the feature is retailer-specific, does the backend need a tenant guard or is frontend-only gating sufficient?

**Cross-service / S2S:**
- Does this ticket touch ServiceC-owned contracts (permissions, roles, SSN masking)? If so, it needs an ServiceC ticket.
- Is a user-facing API being consumed as a service-to-service contract? The auth models differ — does it need a dedicated S2S path?

**Authorization scope:**
- For any permission-mapping change: does each granted action match its scope (a user-level action must not authorize company-wide operations like role management, or sensitive edits like SSN)?

**Deployment:**
- Is a new containerized service/worker being added? If so, `_deploy.yml` needs updating.

**Architecture fit (push back on the ticket):**
- Does the ticket prescribe a *mechanism* (a specific field, endpoint shape, or data location) — especially one relayed from product/customer? Treat it as a suggestion, not a spec: model it the way the system actually works and push back if they diverge. (NOVA-3183: the ticket asked for a `hasSuuntaReporting` boolean on `authorizedFeatures` and "per-user"; the correct model was a company-level `CompanyAction` read via the authorization endpoint — three rework cycles for not settling this first.)
- New permission? Decide UP FRONT: User vs Company scope; contract-gated vs always-on; and which existing feature it mirrors.
- Is anything being added to `authorizedFeatures` for a non-FE consumer? It almost certainly belongs on the authorization endpoints instead.

Output as: *"Before implementation, answer these questions:"* — listed per area. Not as findings, but as design decisions to resolve.

---

## Tips

- Run against a PR before pushing for review: `/ghost-review` (auto-detects current branch)
- Run against a ticket during architecture phase: `/ghost-review NOVA-2547`
- The "Already handled" section is important — it tells you what you can answer immediately if he asks
- Auth-order, multi-tenancy, privilege-scope, S2S-vs-user-API, unit-of-work (SaveChanges in repo), and scope-disposal/N+1 findings are almost always must-fix — fix before requesting review
- Missing integration test findings: cachpachios will always ask. Either add the test (round-trip / access scenario — NOT a unit-logic-path test, which he asks to remove), or pre-empt in the PR description with a linked follow-up ticket
- Cheap pre-empts that recur in his reviews: search endpoints as GET+query, enums/constants instead of raw strings, fail-loud (throw) over silent defaults, Request/Response DTO suffixes, no FQDN in code
