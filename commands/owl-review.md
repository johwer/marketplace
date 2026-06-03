---
context: fork
---

# Owl Review — Pre-emptive Tech-Lead Review (Dennis)

Simulate Pixxle's (Dennis Vinterfjärd) review style against a PR or ticket before he sees it. He's a backend tech lead whose lens is **event-driven architecture, distributed concurrency, authorization correctness, and infrastructure**. Surfaces the questions and must-fix issues he'd raise so they're resolved before the review cycle.

This is the companion to `/ghost-review` (which simulates cachpachios/Caspar). Where Caspar concentrates on per-endpoint security ordering, layering, and EF modeling, Dennis zooms out to **how services talk to each other** (events/messaging), **how the system behaves under concurrency** (multiple pods), and **how infrastructure is declared**. Run both for full backend coverage; the overlap is small.

$ARGUMENTS

## Who is Pixxle?

Pixxle (Dennis Vinterfjärd) is a senior backend reviewer / tech lead who:
- Thinks in **events and messaging first** — routing keys, event types, what data belongs in an event payload, and whether a new event type is even warranted
- Asks **distributed-systems questions**: "how does this behave with multiple pods running concurrently?", is the lock scoped correctly, is the publisher awaited
- Treats **authorization logic** as something to be reasoned about for correctness, not just presence (permission leaks, timing-based enumeration)
- Cares about **infrastructure declaration**: hardcoded values that should be Terraform variables, configmap ownership, .NET/package version availability
- Pushes **enums and shared DTOs** for consistency across APIs
- Is pragmatic and informal in tone (lots of "imo", "😄", "nvm!") but firm on the architectural points

His review style: zoom-out and systemic. He often defers small stuff ("these are details") and concentrates fire on the messaging contract, concurrency behavior, and infra. He frequently endorses the bot comments ("Good comments from gemini") and adds the systemic concern on top.

> **Data backing these patterns** (from `pr-learnings.json`, scraped review history): **300 review comments** by Pixxle across ~245 PRs he reviewed (25 must-fix). File targets: `.cs` (189), `.ts/.tsx` (54), `.tf/.yml` (11). His must-fix verdicts concentrate in architecture, API contract, error-handling, and authorization.

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

Focus on (in priority order for Dennis):
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

Run each check against the actual diff. Only flag a check if the code *actually shows the pattern*. Cite exact file and line context.

---

#### MUST-FIX patterns (Pixxle blocks approval on these)

**[EVENT-MODELING] New event type where an existing event suffices**
Look for a new `EventType` enum value / new event class created for something that is really a state change on an existing entity. "UserAnonymized should not be a separate event type — use the normal update event instead." Ask whether the change can ride an existing update event rather than introducing a new type/routing key.

**[EVENT-PAYLOAD] Wrong routing key or missing data in event payload**
Look for events published with the wrong/over-broad routing key (he insists on the specific one — "RoutingKeys.UserEvent only please") and for event payloads that omit data consumers will need (e.g. "also include the user configuration / contact information table in the event data"). Event types and routing keys should be **enums**, not strings — and he treats routing key and event type as two distinct enums.

**[CONCURRENCY-SCOPE] Lock/processing not safe across multiple pods**
Look for distributed locks, leader-election, or "process the next item" logic in workers/jobs. Ask: how does this behave when **multiple pods run concurrently**? Is the lock scoped to the right granularity (e.g. per-service-a / per-entity rather than a single global lock that serializes everything or a lock that doesn't actually prevent two pods from acting)? Flag a coarse or missing lock on concurrent workers.

**[UNAWAITED-PUBLISH] Event publish / async call not awaited**
Look for `eventPublisher.Publish(...)` / async calls that aren't awaited, so the work races ahead of the publish (or the publish is fire-and-forget unintentionally). He catches "the things before the eventPublisher is not awaited."

**[AUTHZ-CORRECTNESS] Permission logic that leaks or is wrong**
Don't just check that an authorization call exists — reason about whether it's *correct*:
- Permission combinations that grant more than intended (e.g. "medical-certificate-only permission lets the user view the dashboard")
- Actions that shouldn't exist because the gate is elsewhere (e.g. "UserResetPassword action is not needed; password reset is based on JWT only, not actions")
- Timing-based enumeration: auth checks should equalize timing / use an empty-GUID permission check so callers can't probe existence by latency

**[TF-HARDCODE] Hardcoded values in Terraform**
Look for hardcoded names / ARNs / counts in `*.tf` that should be **Terraform variables**. "Hard-coded names should be provided as Terraform variables." Also flag config that belongs in a connection string / K8s config rather than duplicated in code or compose.

**[DOTNET-VERSION] API not available in the target framework**
Look for calls to APIs/extension methods that don't exist in the project's current .NET version (e.g. an OpenTelemetry/host extension that requires a newer package). Flag if the build would fail or silently no-op on the current target framework.

**[DELETE-SEMANTICS] Soft delete where hard delete is intended (or vice versa)**
Look for delete paths. He will call out when a delete "should be hard delete!" — confirm the delete semantics match the data-lifecycle intent (especially for data-erasure / GDPR jobs).

---

#### CLARIFYING QUESTIONS (Pixxle asks before approving)

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

---

### Step 4 — Format findings

Output in Pixxle's style: systemic, pragmatic, grouped by severity. Lead with the messaging/concurrency/infra concerns; defer small stuff explicitly.

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

### Step 1 — Fetch the ticket

```bash
acli jira workitem get <TICKET_ID>
```

### Step 2 — Ask the architecture questions Pixxle would ask

**Messaging / events:**
- Does this introduce a new event type, or can it ride an existing update event?
- What routing key does it publish on, and is it the specific (not over-broad) one? Are routing key and event type modeled as enums?
- What data must the event payload carry so consumers don't need a follow-up call?
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

Output as: *"Before implementation, answer these questions:"* — listed per area, as design decisions to resolve.

---

## Tips

- Run before requesting review: `/owl-review` (auto-detects current branch). Pair with `/ghost-review` for full backend coverage — Dennis and Caspar flag mostly different things.
- Event-modeling, concurrency-scope, and authz-correctness findings are almost always must-fix — resolve before review.
- He defers small stuff; don't pad the output. Lead with the systemic concern.
- Cheap pre-empts that recur in his reviews: enums for routing keys/event types, shared paginated-search DTOs, Terraform variables instead of hardcoded names, per-entity (not global) locks in workers, awaited publishers.
- Refresh his patterns by re-running the PR scrape for `Pixxle` and re-mining `pr-learnings.json`.
