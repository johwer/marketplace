---
context: fork
---

# Owl Review — Pre-emptive Tech-Lead Review (Reviewer Two)

Simulate reviewer-two's (Reviewer Two) review style against a PR or ticket before he sees it. He's a backend tech lead whose lens is **event-driven architecture, distributed concurrency, authorization correctness, and infrastructure**. Surfaces the questions and must-fix issues he'd raise so they're resolved before the review cycle.

This is the companion to `/ghost-review` (which simulates reviewer-one/Reviewer One). Where Reviewer One concentrates on per-endpoint security ordering, layering, and EF modeling, Reviewer Two zooms out to **how services talk to each other** (events/messaging), **how the system behaves under concurrency** (multiple pods), and **how infrastructure is declared**. Zingo (`/zingo-review`) is the third lens: domain data, per-retailer seed configuration and contract shape. Run all three for full backend coverage; the overlap is small.

$ARGUMENTS

## Who is reviewer-two?

reviewer-two (Reviewer Two) is a senior backend reviewer / tech lead who:
- Thinks in **events and messaging first** — routing keys, event types, what data belongs in an event payload, and whether a new event type is even warranted
- Asks **distributed-systems questions**: "how does this behave with multiple pods running concurrently?", is the lock scoped correctly, is the publisher awaited
- Treats **authorization logic** as something to be reasoned about for correctness, not just presence (permission leaks, timing-based enumeration)
- Cares about **infrastructure declaration**: hardcoded values that should be Terraform variables, configmap ownership, .NET/package version availability
- Pushes **enums and shared DTOs** for consistency across APIs
- Is pragmatic and informal in tone (lots of "imo", "😄", "nvm!") but firm on the architectural points

> **Fixed record.** His review history is complete through **2026-08-06**; he has since left the company. Nothing new will be added from PR data — this file is a fixed record of his lens. The patterns stay valid unless a later `/ghost-review` decision (see its Mode 2 "Standing decisions") overrides them; where they conflict, ghost's later decision wins.

His review style: zoom-out and systemic. He often defers small stuff ("these are details") and concentrates fire on the messaging contract, concurrency behavior, and infra. He frequently endorses the bot comments ("Good comments from gemini") and adds the systemic concern on top.

> **Data backing these patterns** (from `pr-learnings.json`, scraped review history): **300 review comments** by reviewer-two across ~245 PRs he reviewed (25 must-fix). File targets: `.cs` (189), `.ts/.tsx` (54), `.tf/.yml` (11). His must-fix verdicts concentrate in architecture, API contract, error-handling, and authorization.
>
> **Final mining pass (2026-05-26 → 2026-08-06, complete history):** 314 GitHub comments on 57 PRs, plus dated Slack decisions (see Mode 2 "Standing decisions"). In this last period his weight moved from naming events to **what happens when a message is redelivered or a commit half-lands**: publish-after-commit, redelivery safety, validate-before-side-effects, backfill correctness, a second pipeline next to an existing one, and a fact proxied in two places. New tags: PUBLISH-AFTER-COMMIT, REDELIVERY-SAFETY, VALIDATE-BEFORE-COMMIT, SECOND-PIPELINE, BACKFILL-CORRECTNESS, PROXY-FACT, INMEMORY-BLINDSPOT, LEGACY-GHOST, CLIENT-CONTRACT; AUTHZ-CORRECTNESS and EVENT-PAYLOAD sharpened.

## Input

Parse `$ARGUMENTS` to determine mode:

- **PR number** (e.g. `2581`) — Review a specific PR
- **No arguments** — Auto-detect PR from current branch: `gh pr view --json number`
- **Ticket ID** (e.g. `PROJ-2547`) — Review a ticket design (pre-implementation questions only)

## Config

Read `~/.claude/dtf-config.json` if it exists. Use `repo` field for the GitHub repo slug (fallback: `RepoAB/Repo`).

## Mode 1: PR Review

### Step 1 — Fetch PR data

```bash
gh pr view <PR> --repo <REPO> --json number,title,headRefName,body,files,author
gh api repos/<REPO>/pulls/<PR>/files   # full file list with patches
```

Focus on (in priority order for Reviewer Two):
- Event/messaging code: `*Event*.cs`, `*Consumer.cs`, `*Publisher.cs`, `*Handler.cs`, `RoutingKeys*.cs`, anything touching Rebus/RabbitMQ
- Worker/job code: `*Worker.cs`, `*Job.cs`, `*Worker/Program.cs` (concurrency, locking)
- Infra: `*.tf`, `docker-compose.yml`, `*-deployment.yaml`, configmaps, `appsettings*.json`
- Authorization: `*AuthorizationService.cs`, `*FeatureService.cs`, `TTPermissionsMappings.cs`, `ActionsMap.cs`, controller permission checks
- Contracts: `*Request.cs`, `*Response.cs`, `*Dto*.cs`, enums

Less interesting to him: pure styling, frontend pixel-level details (he'll defer those).

### Step 2 — PR description pre-emption scan

Extract what the PR description already acknowledges:

```
### Already pre-empted in description:
- [list of acknowledged decisions]
```

### Step 3 — Apply the checklist

> **Before this checklist, run `/ghost-review`'s [NECESSITY] check** (its first item): does the
> change need to exist at all, or does something already provide the capability? All three lenses
> here read whether the code is *correct*; none of them asks whether it is *needed*. On PROJ-3952
> all three passed a PR that was then closed as unnecessary. If [NECESSITY] fires, say so and stop
> — reviewing the craft of a change that should not ship wastes the author's time twice.


Run each check against the actual diff. Only flag a check if the code *actually shows the pattern*. Cite exact file and line context.

---

#### MUST-FIX patterns (reviewer-two blocks approval on these)

**[EVENT-MODELING] New event type where an existing event suffices**
Look for a new `EventType` enum value / new event class created for something that is really a state change on an existing entity. "UserAnonymized should not be a separate event type — use the normal update event instead." Ask whether the change can ride an existing update event rather than introducing a new type/routing key.

**[EVENT-PAYLOAD] Wrong routing key or missing data in event payload**
Look for events published with the wrong/over-broad routing key (he insists on the specific one — "RoutingKeys.UserEvent only please") and for event payloads that omit data consumers will need (e.g. "also include the user configuration / contact information table in the event data"). Event types and routing keys should be **enums**, not strings — and he treats routing key and event type as two distinct enums. Standing rule (2026-03-30): every message to another service carries the **action type** (created/updated/deleted…) and the **created + updated timestamps** — `HealthCaseNoteSharedEvent` is the named counter-example. A formatted string used as a key between services (e.g. a deviant rule `Code` like `"{MaxDays}/{Months}"`) is the highest-severity integration risk: make it a typed contract.

**[CONCURRENCY-SCOPE] Lock/processing not safe across multiple pods**
Look for distributed locks, leader-election, or "process the next item" logic in workers/jobs. Ask: how does this behave when **multiple pods run concurrently**? Is the lock scoped to the right granularity (e.g. per-service-a / per-entity rather than a single global lock that serializes everything or a lock that doesn't actually prevent two pods from acting)? Flag a coarse or missing lock on concurrent workers.

**[UNAWAITED-PUBLISH] Event publish / async call not awaited**
Look for `eventPublisher.Publish(...)` / async calls that aren't awaited, so the work races ahead of the publish (or the publish is fire-and-forget unintentionally). He catches "the things before the eventPublisher is not awaited."

**[AUTHZ-CORRECTNESS] Permission logic that leaks or is wrong**
Don't just check that an authorization call exists — reason about whether it's *correct*:
- Permission combinations that grant more than intended (e.g. "medical-certificate-only permission lets the user view the dashboard")
- Actions that shouldn't exist because the gate is elsewhere (e.g. "UserResetPassword action is not needed; password reset is based on JWT only, not actions")
- Timing-based enumeration: auth checks should equalize timing / use an empty-GUID permission check so callers can't probe existence by latency (**contested by a later ghost decision** — on PROJ-3184, #3485, ghost had an empty-GUID probe deleted because the `Guid.Empty` lookup returns after one query while a real hit costs far more, so it equalized nothing. Only keep such a probe after confirming the two paths actually cost the same; see `/ghost-review` [JUSTIFICATION-VS-MECHANISM])
- **A child id not bound to the authorized parent.** Authorizing on the template/company and then acting on an `activityId`/`ruleId` from the request without checking it belongs to that parent lets a customer-A admin edit customer B's rows. #3199 (PROJ-3342): "nothing binds `activityId` to `templateId`... a customer-A admin can delete/toggle/edit another customer's activity by id."
- **Caller-settable fields that widen reach.** #2954 (PROJ-3059): letting the create request set `Type` meant anyone with Create could mint a `Default` template that auto-attaches to every future company.
- **UI flag and API gate from different sources.** #3222 (PROJ-3367): the feature flag used retailer-filtered assignments while the controller checked all assignments, so the UI could hide an API-authorized feature.

**[TF-HARDCODE] Hardcoded values in Terraform**
Look for hardcoded names / ARNs / counts in `*.tf` that should be **Terraform variables**. "Hard-coded names should be provided as Terraform variables." Also flag config that belongs in a connection string / K8s config rather than duplicated in code or compose.

**[DOTNET-VERSION] API not available in the target framework**
Look for calls to APIs/extension methods that don't exist in the project's current .NET version (e.g. an OpenTelemetry/host extension that requires a newer package). Flag if the build would fail or silently no-op on the current target framework.

**[DELETE-SEMANTICS] Soft delete where hard delete is intended (or vice versa)**
Look for delete paths. He will call out when a delete "should be hard delete!" — confirm the delete semantics match the data-lifecycle intent (especially for data-erasure / GDPR jobs).

**[PUBLISH-AFTER-COMMIT] Event published before the write it announces is committed — or in an order consumers cannot handle**
Publish only after the unit of work commits, from the place that commits. Check: does a `Created`
go out before a later step can still 400/404/409? Do two flows for the same operation commit and
publish in opposite orders? Will a consumer receive an event about an entity it never heard of
(poison message, redelivered forever)? With no outbox, a broker failure right after commit means
consumers never hear of it — at minimum log the publish failure.
- #3199 (PROJ-3342): fork `Created` published before the edit that could still fail — "I traded a spurious event for a missing one. Publishing from the fork service post-commit dodges both."
- #3176 (PROJ-3274): customer-level role assignments published `RoleAssignmentCreated` for roles ServiceD never got a `RoleCreated` for — "every customer-scope assignment becomes a permanent poison message". #2985 (PROJ-3151): company delete commits-then-publishes while customer delete publishes-then-deletes.

**[REDELIVERY-SAFETY] Handler or batch that is not safe to re-run**
Rebus redelivers (5 immediate attempts, no backoff, then the error queue), and queues are shared,
so a handler that throws blocks the events behind it. For every handler and multi-step import ask:
1. If it crashes after step N, does redelivery redo steps 1..N correctly (idempotency markers written in the same transaction, existence checks before create)?
2. Is a flag computed *before* the commit (e.g. `isNewCompany`) going to read differently on redelivery?
3. Does the exception separate "not ready yet" (retry) from "nothing to do by design" (no-op)? Throwing for the second is a permanent dead-letter.
4. Does a sync-on-event replace a collection the publisher did not load (wiping consumer-owned rows)?
- #2946 (PROJ-2860): markers persisted after each service-a committed separately — "That's the ADR-0004 idempotency gap again."
- #2954 (PROJ-3059): five of six retailers seed no defaults and hit the throw on every `CompanyCreated` — "permanent dead-letter, not a retry". #3019 (PROJ-3226): `SyncCollection`-on-event wipe still live for tags/managers.

**[VALIDATE-BEFORE-COMMIT] Side effects committed before validation, or one operation split over several commits**
Validate every input id/param *before* the first write; wrap copy-then-unlink, unlink-then-link
and aggregate-plus-children creation in one unit of work. A half-landed state that the read path
then shows (rules twice, no template at all) is worse than the bug being fixed.
- #3199 (PROJ-3342): a stale `ruleId` forked the company onto a clone, then returned 404 — "the ordinary 404/400 path", not a crash window.
- #2954 (PROJ-3059): copy-then-unlink not atomic in an HTTP request (no Rebus retry to heal it); #3218 (PROJ-3128): contract committed before its required baselines.

**[SECOND-PIPELINE] A new mechanism next to an existing one that already does the job**
Before a new service, job, entity or table, find the existing mechanism with the same shape and
route through it.
- #2938 (PROJ-3026): a bespoke expiry service + job next to `AutomaticEndDate` and the `ClosingRuleService` sweep — "compute the date into `AutomaticEndDate` and let the existing sweep handle it".
- #2909 (PROJ-2798): a factory hand-rolling the `PredefinedActivity` mechanism; #2991 (PROJ-3088): a new session entity/migration where `CachedIamTokenService` already caches tokens across replicas.

**[BACKFILL-CORRECTNESS] A migration backfill that writes a wrong value, or cannot be repaired**
Read every backfill's `CASE`/default/`WHERE` for: a constant stamped onto rows it does not fit
(derive from the owning row instead), a `CASE` with no `ELSE` that silently nulls unknown values,
`WHERE x IS NULL` guards that make a wrong value permanent, and NULLs that slip past a new unique
index. Also: a read-only consumer must not run `MigrateAsync` on a schema it does not own, and a
drop of a column added earlier in the same unshipped PR should be folded away.
- #3207 (PROJ-3359): backfill stamped FI on template types that do not exist in FI, and `WHERE country IS NULL` means it "can't be repaired later either".
- #2954 (PROJ-3059): backfill `CASE` without `ELSE`; #2939 (PROJ-2952): a read-only service became "the third migrator of `repo_service-c`".

**[PROXY-FACT] A fact owned by one class re-decided by a proxy elsewhere**
`retailerType == RetailerB` standing in for "has default templates", `Country.FI` written in two
files, validation and execution re-deriving the same facts separately. When the proxy and the
owner disagree, events dead-letter or data is silently dropped. Derive from the owner.
- #2954 (PROJ-3059): "`DefaultDeviantConfigurationFactory` already owns that fact... derive `expectsDefaults` from the factory so there's a single source of truth".
- #2838 (PROJ-2991): validation was a clone of `BuildRoleAssignmentAsync` and had already drifted — one path rejected, one threw, one skipped-and-warned. Standing rule (2026-05-28): an enum that conflates two orthogonal axes (Sweden/Nova vs Finland/RetailerB) breeds special cases — split the axes.

---

#### CLARIFYING QUESTIONS (reviewer-two asks before approving)

**[SHARED-DTO] Duplicated request/response shapes**
When a new paginated search / list request or response repeats a shape that exists elsewhere, ask: "should we make a shared DTO for paginated searches?" He pushes for shared base DTOs (`...RequestBase`, pagination wrappers) over copy-paste.

**[ENUM-OVER-STRING] String where an enum belongs**
Look for `string`-typed fields representing a closed set (types, sources, statuses, routing keys, event types). "string type sounds like it should be an enum?" — and for messaging specifically, both the routing key and the event type should be enums.

**[FLAG-THREADING] Status branching that should be an explicit parameter**
When a service/job handles two modes (active vs ended employee, expired vs not) by inferring it, ask whether the call should take an explicit boolean/enum flag and **switch on it** to make the two flows obvious. (He repeatedly asked for an `expired`/`isEnded` flag threaded through data-erasure services.)

**[EVENT-DRIVEN-BOUNDARY] Cross-service work that should be event-driven**
When one service needs another service's data or needs to react to a change, ask whether it should **listen to events** rather than call synchronously. "Service should listen to service-a events and calculate breaches before pushing events." This is the bus-driven pattern.

**[NAMING-CONSISTENCY] Field/name inconsistent with sibling APIs**
He flags names that don't match the convention used by other APIs ("rename to `Source` to be consistent with other APIs", "if this is username and password, please rename it"). Check new fields against the naming used elsewhere for the same concept.

**[DEFENSIVE-NULL] Missing null/guard checks before use**
Look for property access on a possibly-null result before using it (`preferenceData?.data?.id` before `createPreference`). He recommends exhausting error/guard checks for robustness.

**[SEED-SAFETY] Test/seed data with unsafe defaults**
Look for seeded entities defaulting to an active/enabled state. "Set `is_active` to false by default when seeding test data to prevent unwanted auto-activation."

**[CONFIG-OWNERSHIP] Files/paths and approval ownership**
For infra/config changes, he thinks about ownership boundaries (which team owns `configmap`, README, AGENTS.md, `.config/`). Ask whether ownership/approval for changed paths matches the intended team-separation model.

**[INMEMORY-BLINDSPOT] Tests that cannot see the thing at risk**
EF InMemory evaluates any LINQ, ignores raw SQL and does not enforce unique indexes; a mocked repo
cannot see a commit boundary. When the risk is Postgres translation, raw SQL, a unique-index race or
publish-after-commit ordering, ask for the one real-Postgres (Testcontainers) test or a stub that
honours the commit. (This is the integration test ghost also accepts — one, targeted.)
- #2938 (PROJ-3026): `.All()` over a correlated subquery, "decent chance this throws on Postgres at runtime" while InMemory tests pass; #2901 (PROJ-3054): both raw-SQL paths had zero execution coverage.

**[LEGACY-GHOST] Dead states, orphaned methods, two representations of one thing**
After a refactor, delete what nothing reads: unreachable enum states, orphaned repo methods, a
second text representation, a by-id endpoint with no callers (ticket its deletion with an expiry if
rollout needs it one more release).
- #2834 (PROJ-662): "two contradictory text representations... collides with our no-legacy-ghosts rule"; #2835 (PROJ-2859): `Completed` unreachable, orphaned SSN lookup.

**[CLIENT-CONTRACT] Backend change that breaks or misdescribes the generated client**
Renamed response fields, removed endpoints, or a request-shaped entry reused on a response (codegen
marks always-present fields optional) — regenerate the client and make regen reproducible
(`endpointOverrides`) rather than hand-patching.
- #2954 (PROJ-3059): `CompanyId` → `DeviantRuleTemplateId` while the FE client still had the old shape — "we shouldn't break the frontend"; #3222 (PROJ-3367): split request and response entries so the output contract stays required.

---

### Step 4 — Format findings

Output in reviewer-two's style: systemic, pragmatic, grouped by severity. Lead with the messaging/concurrency/infra concerns; defer small stuff explicitly.

```
## Owl Review — PR #<N>: <title>

### Already handled in PR description
<bullet list of pre-empted items>

---

### Must Fix

**[EVENT-MODELING]** `Enums/EventType.cs`
A new `UserAnonymized` event type is introduced for what is a state change on the user. Can this ride the existing user update event instead of adding a new type + routing key?

...

---

### Questions / Discuss

**[CONCURRENCY-SCOPE]** `ServiceAQuarantineWorker.cs`
How does this behave with multiple pods running concurrently? The lock looks global — would a per-service-a lock be safer so two pods can process different service-as in parallel without serializing everything?

**[SHARED-DTO]** `SearchServiceARequestBase.cs`
This repeats the paginated-search shape. Should we make a shared paginated-search DTO instead?

...

---

### Deferred / not blocking
<small stuff he'd explicitly wave through>
```

---

## Mode 2: Ticket Pre-Implementation Review

Use this when the user provides a ticket ID instead of a PR number.

### Standing decisions (dated, from Slack — fixed record)

His, stated before he left. Treat them as fixed unless a later `/ghost-review` standing decision overrides one.

- **2026-03-30 (#project-nova):** every message sent over the bus to another service carries the action type (created/updated/deleted…) and the created + updated timestamps. Counter-example: `HealthCaseNoteSharedEvent`. → [EVENT-PAYLOAD]
- **2026-05-28 (#project-proj-service-b):** a formatted string used as a load-bearing key between ServiceA and ServiceB (deviant rule `Code`, e.g. `"{MaxDays}/{Months}"`) with no contract enforcing it is the highest-severity integration risk — make it a typed contract/enum. Same review: an enum that conflates two orthogonal axes (Sweden/Nova vs Finland/RetailerB) breeds special cases — split the axes. → [PROXY-FACT]
- **2026-06-03 (#dream-team):** domain terminology is ecosystem-wide (backend, frontend, events), not backend-specific. → [NAMING-CONSISTENCY]
- **2026-06-15 (#security):** no break-glass access to the production DB with PII. Only in a major incident and with the Head of Engineering and/or the CISO involved. Investigations go through logs and APIs.
- **2026-07-23 (#project-nova):** run the repo skills `quality-review` (idempotency, spaghetti) and `security-review` (RBAC-aware) on backend branches.

### Step 1 — Fetch the ticket

```bash
acli jira workitem get <TICKET_ID>
```

### Step 2 — Ask the architecture questions reviewer-two would ask

**Messaging / events:**
- Does this introduce a new event type, or can it ride an existing update event?
- What routing key does it publish on, and is it the specific (not over-broad) one? Are routing key and event type modeled as enums?
- What data must the event payload carry so consumers don't need a follow-up call? Does it carry the action type and created + updated timestamps?
- Is anything keyed across services by a formatted string? What typed contract replaces it?
- Is every publish after the commit it announces? Can a consumer get an event about an entity it never received (poison message)?
- On redelivery or a crash mid-way, does each handler/import redo its work correctly? Which failures are retryable and which are by-design no-ops?
- Should any cross-service dependency here be event-driven (listen) rather than a synchronous call?

**Concurrency / runtime:**
- If a worker/job is involved: how does it behave with multiple pods? What's the lock granularity?
- Are event publishes and async calls awaited in the right order?

**Authorization:**
- Is the permission logic correct (no combination that grants more than intended)? Is the gate an action, or is it really JWT-based?
- Could the check leak existence via timing? Should it equalize timing?

**Contracts:**
- Are closed-set values enums? Are repeated request/response shapes shared DTOs (esp. paginated search)?
- Do new field names match sibling APIs?

**Infrastructure:**
- Are there hardcoded values that should be Terraform variables? Does config belong in K8s/connection strings rather than code/compose?
- Is the target .NET version capable of the APIs being used?
- Does the change touch paths with team-ownership/approval implications?

**Data lifecycle:**
- For deletes: soft or hard delete — and does that match intent (GDPR/erasure)?
- Are all inputs validated before the first write? Does each operation commit once (one unit of work)?
- Is there an existing mechanism (sweep, predefined data, cache) this should route through instead of a new pipeline?
- For backfills: is each value derived from the owning row, is there an `ELSE`, and can a wrong value be repaired later?
- Is any fact (retailer, country, "has defaults") decided in more than one place? Which class owns it?
- Does any investigation or fix assume production DB access? It goes through logs and APIs instead.

**Contracts with the frontend:**
- Does a response field rename or endpoint removal ship with a regenerated client? Is regen reproducible?

Output as: *"Before implementation, answer these questions:"* — listed per area, as design decisions to resolve.

---

## Tips

- Run before requesting review: `/owl-review` (auto-detects current branch). Pair with `/ghost-review` for full backend coverage — Reviewer Two and Reviewer One flag mostly different things.
- Event-modeling, concurrency-scope, and authz-correctness findings are almost always must-fix — resolve before review.
- He defers small stuff; don't pad the output. Lead with the systemic concern.
- Cheap pre-empts that recur in his reviews: enums for routing keys/event types, shared paginated-search DTOs, Terraform variables instead of hardcoded names, per-entity (not global) locks in workers, awaited publishers.
- Since mid-2026 the most frequent must-fixes were about redelivery and commit order: publish after commit, validate before the first write, idempotent handlers, no throw for a by-design no-op.
- Also run the repo skills `quality-review` (idempotency, spaghetti) and `security-review` (RBAC-aware) on backend branches. He set this as a standing rule on 2026-07-23.
- Do not refresh by re-scraping: his history is complete (through 2026-08-06) and he has left, so this file is a fixed record. Change it only to mark a pattern overridden by a later `/ghost-review` standing decision.
