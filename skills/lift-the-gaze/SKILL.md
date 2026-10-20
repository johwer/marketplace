---
name: lift-the-gaze
description: Lift the gaze before writing backend code — find the highest place a decision can live (product scope, contract, retailer, feature flag, ServiceC permission, endpoint) so the layers below never have to handle it; then ball 2-3 architectural options with the user, spell out each one's consequences, and check that what remains lands in the right backend layer (Controller → Service → Domain/Repository, DTO vs entity). Teaching mode, not a gate. Use when a ticket or plan asks "which controller/service/repository do we change", when a feature is only for one retailer or behind a flag, when the user says "lyft blicken", "bolla alternativ", "var ska det här ligga", "vilket lager", "why do we need a DTO", or wants to understand the backend architecture of a change.
user_invocable: true
---

# Lift the Gaze

The user is stronger on frontend than backend. This skill does three things, in this order:

1. **Altitude** — before discussing *which* controller/service/repo to change, ask whether the question disappears if the decision is made higher up.
2. **Ball the options** — 2-3 real alternatives, one question at a time, each with its consequences. The user decides.
3. **Layer placement** — for the code that remains, show which layer each piece belongs in and what it looks like when it lands in the wrong one.

It is a conversation that teaches, not a review that blocks. Talk in the user's language (Swedish if they write Swedish). Keep each turn short: one diagram, one table, one question.

Reference material: `references/layers.md` (Repo layer map, wrong-place symptoms, why DTOs). Visual explainer: `layers.html` in this folder, published at https://claude.ai/artifact/STniiXQ7hda1GrUTifKkMU — link it when the user wants the picture.

---

## Step 0 — Read before you talk

**Load what the tech leads already decided, before forming any option.** The reviewer patterns live in two commands; this skill reads them and never copies them:

- `~/.claude/commands/ghost-review.md` — the current backend tech lead. Read: "Standing decisions" (dated rules from Slack/Jira, e.g. "the contract is the switch", "use services, not products", migration tooling must keep up), the `[NECESSITY]` check (what already provides this? constraint or convention? config or code? shared rule → prealign), and "Mode 2" Step 2 questions.
- `~/.claude/commands/owl-review.md` — the former tech lead (left 2026-08; a fixed record). Read its "Standing decisions" and Mode 2 questions for events, concurrency and contracts. A later ghost decision overrides it.

**Know which skill answers what.** Route instead of improvising:

| Need | Skill |
|------|-------|
| What the tech leads already decided; what they'd flag | `ghost-review`, `owl-review` (Standing decisions, Mode 2 questions) |
| How this is usually done in .NET / the textbook view (layers, clean architecture, DDD, events, outbox, gateway, resilience) | `dotnet-architecture-reference`. Generic; never overrides a standing decision |
| Is this EF query / transaction / async / config / DI lifetime right? (once the layer is chosen) | `dotnet-backend-review`. Repo-checked; lists textbook advice we declined |
| Was this decided by the team, CTO or another dev (not a tech lead)? | `backend-decisions`. Dated, era-tagged; tech-lead decisions stay in ghost/owl |
| Repo conventions (naming, ApiResponse, DTO mapping, EF) | `backend-conventions` |
| Two or more radically different interface shapes | `design-an-interface` |
| A whole module that's hard to work in | `improve-codebase-architecture` |
| API contract leaks (entities in signatures, missing DTOs) | `ln-643-api-contract-auditor` |
| Query/latency cost of an option | `backend-performance` |
| Domain terms or an ADR need writing down | `grill-with-docs` |
| A question that belongs to PO or tech lead | `stakeholder-questions` (after Step 2b) |
| Recording the decision in the PR | `pr-decisions` |
| A diagram | `mermaid-diagram` |

Naming a skill in this table loads nothing. Invoke it, or read its `SKILL.md`, before using what it says, and never report a skill as consulted because it was named.

Any option that contradicts a standing decision is dropped before the user sees it, or shown only with the decision quoted and why it might not apply. Cite the decision (date + source) in the option card.

Then read the ticket/plan, the parent epic and sibling tickets (decisions are often recorded there), and find the real code it touches. Do not reason from layer names alone.

- Which service(s)? `services/<Domain>/<X>.API` (Controllers, Services, Models/DTOs, Handlers) and `<X>.Domain` (Models = entities, Repository, Policies, shared Services, Mappers).
- Who reaches this code? Endpoint only, or also Rebus handlers and `*.Worker.*` projects? A gate on the controller does not cover a worker.
- Who actually has access to the feature today? (retailer, contract, permission, PostHog flag). Grep, don't assume.

## Step 0.5 — What kind of problem is this?

Before choosing *where* a decision lives, name *what kind* of problem it is. Turn off the code brain for one turn. Two to four short questions, only the ones whose answer isn't already known.

**Context, ask only what is unknown:**

| Question | Known Repo default (don't ask again) |
|---|---|
| What is the actual problem or bottleneck? A symptom, a ticket, a number? | Always ask if the ticket doesn't say. "It's slow" is not a problem statement |
| Current architecture | Known: .NET microservices, Rebus events, replicas per service, ServiceC over HTTP. Don't ask |
| Constraints: scale, time, team, budget | One live prod customer, so a manual switch-on is reasonable (2026-10-16). The SignedIn migration is in flight. Ask only about deadlines the ticket doesn't state |

**Four lenses, each with the Repo default:**

| Lens | Question | Repo default |
|---|---|---|
| Data or logic | Is the pain in the code, or in the data (index, lock, query shape)? | **Measure first.** A performance question goes to telemetry (Elastic) and `backend-performance` before any redesign. Without numbers it's a guess |
| Sync or async | Must this happen while the user waits? | An event published after commit is fine for side effects. **Never** a request emulated over the bus, and no "200 = queued" for a write the caller relies on ([BUS-IS-NOT-RPC]) |
| Reads or writes | Is the load lopsided? | Replicas via events (the owning service enriches), Dapper for heavy reads, cache only with invalidation ([CACHE-INVALIDATION]). Writes through a worker were rejected (2025-08-18) |
| Operational simplicity | Are we solving a problem we don't have? | Existing mechanism first; something new needs taste, judgment and consensus (2026-10-16, [NECESSITY]). Fewer, bigger services is the direction (ServiceC merged 2025-01) |

**Measure, don't guess (data or logic lens).** For a performance or "it's slow / it fails" question, fetch numbers before proposing anything. The Elastic MCP tools (`mcp__claude_ai_Elastic_mh-accept__*`, load them via ToolSearch) read the **accept** environment:

1. `observability_get_services` (start `now-24h`): find the service. Only the APIs and `service-c-sync-worker` have APM traces (service-a-api, service-c-api, service-d-api, service-b-api); service-e-api, billing-api and the workers show up in logs only.
2. `observability_get_trace_metrics` with `kqlFilter: 'service.name: "service-a-api"'`, `groupBy: "transaction.name"`, `latencyType: "p95"`: which endpoint is slow or failing.
3. `observability_get_traces` for that transaction: the spans show where the time goes (SQL, an ServiceC call, a loop of calls = N+1).
4. `observability_get_logs` / `observability_run_log_rate_analysis`: errors and spikes, for workers and services without traces.

What the numbers can and cannot say: accept has little traffic and test data. Use it for **where the time goes inside one request** (span breakdown, number of SQL or ServiceC calls) and for error patterns, not for **how slow production is**. There is no prod connection here; ask the user for prod figures when the decision depends on scale. Put the numbers in the one-line answer, e.g. "p95 600 ms on GET /service-as, 40 ServiceC calls per request → a data/N+1 problem, not an architecture problem."

**Generic advice that does not apply here, so don't offer it:** an API gateway or BFF to absorb orchestration (ruled out 2025-12-03); CQRS through workers; switching to another architecture style as the fix for one ticket. "Invert dependencies" applies at the API edge only: the DTO protects the contract, while entities deliberately match the tables.

Write the answer as one line before Step 1, e.g. "Logic problem, synchronous, read-heavy, no new mechanism needed."

## Step 1 — The altitude ladder

Walk this ladder top-down and stop at the **highest rung that can carry the decision**. Every rung you can stop at higher up deletes branches in every rung below.

| # | Rung | Repo mechanism | It answers |
|---|------|-------------------|------------|
| 0 | Scope | The ticket itself | "Does anyone without access need this at all?" |
| 1 | Contract / entitlement | `ServiceContract`, `SubContract` (`shared/Repo.Shared.Models/ServiceContracts`), e.g. `ICallbackEntitlementReader` | "Has the customer bought it?" |
| 2 | Retailer | `RetailerType`, `CanDoActionOnRetailer`, retailer-targeted PostHog flags | "Is this only RetailerB / only one brand?" |
| 3 | Feature flag | PostHog (frontend; backend only in ServiceD via `IFeatureFlagService`) | "Is this a rollout we may need to roll back?" Not a substitute for a contract: when a service contract exists, the contract is the switch |
| 4 | ServiceC permission | `ServiceCAuthorizationAdapter.CanDoActionOn*` (BE), `AuthorizedFeatureMap`/`SettingsMap` (FE menu) | "May *this user* do it?" |
| 5 | Endpoint | `[AcceptTokens]`, `[Authorize]`, controller validation | "Is the request well-formed and allowed?" |
| 6 | Service / Policy | `*.API/Services`, `*.Domain/Policies` | "What is the business rule?" |
| 7 | Repository | `*.Domain/Repository` | "Which rows?" |
| 8 | Database | constraints, indexes | "What must never be stored?" |

For the chosen rung, list concretely **what code you no longer need lower down** ("no null-handling for companies without the contract in the export mapper", "no retailer branch in `XService`"). That list is the payoff — show it.

### The four traps of a high gate (always check)

- **A frontend gate is UX, not security.** Hiding a menu with a PostHog flag or `SettingsMap` does not stop `curl`. If the data is sensitive, the endpoint still needs rung 4/5. Real example: `services/ServiceD/ServiceD.API/Controllers/SupportController.cs` — for non-RetailerB retailers the page is gated in the frontend only, so the endpoint asks for nothing beyond a signed-in user. That was a deliberate choice; make it deliberate every time.
- **A flag is temporary.** When the flag is removed, everyone gets the code. Either the lower code is correct for everyone by then, or the flag must become a contract/permission (a permanent rung). Ask: "What happens the day this flag is deleted?"
- **Workers and events bypass controllers.** A check on rung 5 does not cover a Rebus handler or a worker. If both paths need the rule, it belongs in `*.Domain` (Policy or shared reader), like `ICallbackEntitlementReader` which the API and the callback engine share.
- **Data written while gated still exists.** Turning a flag off hides the UI, not the rows. Reads elsewhere (ServiceE, exports, data erasure) still see them.
- **The migration tooling must keep up.** A new enum value, a new `ServiceContractType`, a schema change or a changed field meaning also needs the SignedIn→Nova migrators (`ServiceContractMigrator`, `HealthCaseTemplateRuleMigrator`, …) updated, or migrated customers get no access / broken data. A high gate built on a contract only works for migrated customers once the migrator grants it (precedent: PROJ-4408).

When the fix is to **data** rather than behaviour, there is a rung above a DB migration: correct it through the existing API or config. A migration is fine, but overkill when an API can do it.

### Existing before new (applies to every option)

Rank options by what they build, not only by altitude: **existing mechanism (API, config screen, manual step) → migration, only when needed to avoid data loss → new mechanism, only with consensus first.** Tech lead 2026-10-16: "Always be careful about building a mechanism we dont have… Something new needs taste, judgment and consensus. Something existing is just to go hard." A manual step is a real option, not a failure: with one live prod customer, "manual turning stuff on is reasonable". In each option card, mark whether it uses something that exists or builds something new; a "new" option without prior agreement goes to the tech lead before it is recommended.

## Step 2 — Ball the options

Present 2-3 options that differ in **altitude**, not in style. One per rung that is genuinely viable. For each:

```
Alternativ A — <one-line name> (rung N)
  Var:          <file/layer it lands in>
  Försvinner:   <code we no longer write lower down>
  Konsekvens:   <see card below — only the rows that differ between options>
```

Consequence card (pick the rows that actually differ):

| Dimension | Question |
|-----------|----------|
| Kod längre ner | How many branches/null-checks/tests disappear or appear? |
| Säkerhet | Can it be bypassed by calling the API directly? |
| Livslängd | Temporary rollout or permanent business rule? |
| Vem ändrar | PO in PostHog without deploy, or a developer with a deploy/migration? |
| Täckning | Does it cover workers, events, exports, other services? |
| Återställning | Can we turn it off? What about data already written? |
| Kopplingar | Does it add a cross-service call (ServiceC, ServiceB)? Latency, failure mode? |
| Test | What test proves it, and at which level (unit / integration / e2e)? |

Then **recommend one** and say why in one sentence. Ask **one** question at a time — the one whose answer changes the design most. Don't dump every question. Wait for the answer before the next.

When an answer depends on someone else (PO: "is this only ever for one retailer?", tech lead: "is a FE-only gate acceptable here?"), first run Step 2b. Only what survives it goes to `stakeholder-questions`.

## Step 2b — Lift the gaze on the questions too

A question costs someone else's time and blocks us until it is answered. Before sending one, check whether it is already answered higher up:

1. **Collect the principles already given.** Read the ticket's comments and description, the parent epic and sibling tickets (decisions are often recorded there, e.g. "Tech lead answers <date>"), the spec, and earlier turns of the session. Quote them with date and source.
2. **Test each draft question against them:**

| Verdict | When | Where it goes instead |
|---------|------|-----------------------|
| Answered by a principle | A given rule decides it ("use the services", "the contract is the switch", "no change vs SignedIn") | A recorded decision in the spec / `pr-decisions`, quoting the principle |
| Our own call | Naming, implementation shape, which existing pattern to copy | PR Decisions section |
| Dependency, not a question | The pattern is set and only the work remains (e.g. a migration step like a previous ticket) | A subtask |
| Known limitation | Low impact, no data exposure, small parity deviation | One line in the PR |
| Real question | None of the above, and the answer changes the design | `stakeholder-questions` |

3. **Prefer "decide and inform" to asking.** When everything is covered by the first four rows, send one line in the form "Going with X, because <principle>. Shout if you disagree, otherwise it's in the PR." It costs the reader seconds and doesn't block us.

Show the user this table for their draft questions before writing any question.

4. **Make the risk concrete instead of asking open-ended.** "Is this OK?" costs the reader a whole investigation. Check who calls it, how it deploys, what breaks and whether data is lost, and send "this is the window, this is the effect".
5. **Have the fallback ready.** Name the next step if the answer is no (expand/contract across two releases; the bigger change as its own ticket), so a "no" doesn't restart the design.
6. **Let the PR carry the question.** Write the decision in the PR (Chose / Over / Why / Risk / Fallback), mark it ready and request the tech lead as reviewer. The tech lead decides in review, nothing waits on a side message, and the decision stays next to the code.

In one sentence: find who owns the decision, use what exists, measure the risk, have a fallback ready, and let the PR ask the question.

### Worked example (2026-10-20): PROJ-4405 and PROJ-4406

| | PROJ-4405: duplicate subscriptions | PROJ-4406: who the target picker shows |
|---|---|---|
| Hard part | One POST did both "add" and "edit (replace)". Making it create-only (409 on duplicate) breaks edit, so edit needs a PUT. That changes an endpoint's meaning while old clients run: ServiceD before web = 409 on edit for a few minutes. Plus two concurrent adds (advisory lock) and the merge order with PROJ-4423 | The ServiceC user search can't filter on an action (`UserSubscriptionManage`), and the ticket said no ServiceC change. A (company filter) leaks other departments to a department admin; C (filter in ServiceC) is cleanest but an ServiceC change |
| Who owns it | API_CONVENTIONS: POST creates, PUT updates | ServiceC owns authorization, so reuse its answer (`POST authorization/users`) |
| Existing, not new | No new create-only route (it would leave POST as replace for good) | B′ = search ∩ `authorization/users`, no ServiceC change |
| Real question left | Is a few minutes of 409 on rollout acceptable? | Is the web as first caller of an S2S-only endpoint, with a large `limit`, acceptable? |
| Risk made concrete | Only `apps/web` calls the POSTs; prod deploys backend then web in one workflow; effect is a visible 409 in admin flows, no data loss; open tabs keep old JS until reload | Response size and call time measured on accept (Elastic, service-c-api) |
| Fallback | Expand/contract: release 1 adds PUT and moves web, release 2 makes POST create-only | (C) as its own ServiceC ticket |
| How it was asked | PR ready, tech lead requested as reviewer | Same |


## Step 3 — Layer placement

For what remains, walk the request down the layers and place each piece. Use `references/layers.md` for the full table. Short version:

| Layer | Belongs here | Wrong-place smell |
|-------|--------------|-------------------|
| Controller | HTTP, token type, shape validation, ServiceC check, call the service and return its `ApiResponse<T>` | `if (retailer == …)` business rules, EF queries, `DbContext` |
| Service (`*.API/Services`) | Orchestration, business rules for this API, ServiceC/other-service calls, publish events, returns `ApiResponse<T>` (Repo convention, `CODING_STYLE_BACKEND.md:521`) | `HttpContext`, raw SQL, a rule a worker also needs |
| Domain (`*.Domain`) | Entities, Repositories, Policies, shared readers used by API **and** workers | Knowing about HTTP, DTOs or `ApiResponse` |
| Repository | Queries, filters, includes, projections | Deciding *whether* the user may see it (that's a rule) |
| DTO (`*.API/Models/DTOs`) | The contract with the frontend (becomes RTK types via `generate-api`) | An EF entity returned straight from a controller |

Then draw it. Load the `mermaid-diagram` skill first for syntax (quote labels with special characters, no reserved words), and pick the diagram type by what the user needs to see:

| Need to see | Diagram |
|-------------|---------|
| Where the gate sits and which layers are touched | `flowchart` (default, example below) |
| One request walking down the layers, incl. the ServiceC call and the response back | `sequenceDiagram` |
| What happens over time: flag on → flag removed, contract added → cancelled | `stateDiagram-v2` |
| Entity vs DTO fields, what leaves the service | `classDiagram` or `erDiagram` |

One diagram per turn. Default flowchart of the actual change, with the gate and the touched layers highlighted:

```mermaid
flowchart LR
    FE[Frontend<br/>PostHog flag]:::gate --> C[XController]:::touched
    C -->|CreateXRequest DTO| S[XService]:::touched
    S --> P[XPolicy<br/>Domain]
    S --> R[XRepository]
    R -->|Entity| DB[(Postgres)]
    W[X.Worker] --> P
    classDef gate fill:#fde68a,stroke:#b45309,color:#111
    classDef touched fill:#bfdbfe,stroke:#1d4ed8,color:#111
```

Mark the gate (`gate`), what this change touches (`touched`), and any path that bypasses the gate (worker, handler) with a dashed edge `-.->`.

### DTOs — explain when it comes up

Entity = how the database stores it. DTO = what we promise the frontend. They change for different reasons, so they must be different types. Full explanation and the cost side in `references/layers.md#why-dtos`.

## Output

Each turn: at most one diagram, one table, one question. End the session with a short summary:

```
Beslut: <option> på nivå <rung>
Slipper: <what we don't build lower down>
Kvar att bygga: <layer → file>
Risk vi accepterar: <the trap we consciously accept, if any>
```

Don't write code. Don't edit tickets or post anywhere. If the user wants the decision in a PR, hand off to `pr-decisions`; into the ticket spec, to `ticket-spec`.
