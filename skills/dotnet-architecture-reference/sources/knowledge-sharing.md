# #knowledge-sharing reading list (digested)

- **What this is:** the freely readable articles from Slack #knowledge-sharing that are worth a backend developer's time, each digested in our own words. Mined 2026-10-17 over the whole channel history (2023-10-20 → 2026-10-15).
- **Who shared them:** almost all by the former backend tech lead (the person behind `~/.claude/commands/owl-review.md`, who left 2026-08). The current tech lead (`ghost-review.md`) posted one link in the channel, a .NET tips list, noted at the end.
- **Copyright:** each article belongs to its publisher. Nothing is copied here; notes are paraphrase only. The Google review guide is CC BY 3.0 (repo `LICENSE`); 12factor.net and the others state no open licence, so treat them as all rights reserved.
- **Already recorded elsewhere:** the 2025-10-02 concurrency-token tip (`owl-review.md:102,365`) and the 2026-03-11 inbox/outbox post (`owl-review.md:98,384`). The inbox/outbox article is still digested below because the decision line in owl does not carry the article's detail.
- **Not here:** videos (talks on nesting, timezones, data-oriented design, Postgres-for-everything, AI-agent workflows) and tool or news links. See the source list in the Slack report for those.
- The cognitive-load essay (shared 2024-06-20) has its own file: `cognitive-load.md`.

---

## Google engineering practices: the code reviewer's guide

- **URL:** https://google.github.io/eng-practices/review/reviewer/ (sub-pages `standard.html`, `looking-for.html` read)
- **Shared:** 2023-10-21, former tech lead, noting it as something to follow more closely himself.

Takeaways:
- Approve once a change clearly improves the health of the codebase. The bar is "better", not "perfect", and a change should not stall over polish.
- Facts and data beat opinion. The style guide settles style; anything it does not cover is preference, so follow the surrounding code.
- Label non-blocking teaching comments as optional ("Nit:") so the author knows what must change.
- Look hardest at design, then behaviour (edge cases, concurrency), then complexity. Flag code that is more generic than today's problem needs.
- Tests must be able to fail when the code breaks. Comments should explain why, not what.
- Read the change in the context of the whole file and system, not only the diff. If author and reviewer stall, talk live and record the outcome on the PR.

Repo relevance: the over-engineering point is [SPECULATIVE-GENERALITY] and [NECESSITY]; "comments explain why" matches [COMMENT-NOISE] and the repo's no-comments rule; "read the whole file" is what `hard-simplify` does. The "nit:" convention is the cheapest way to keep ghost/owl-style reviews from reading as all-blocking.

---

## The Twelve-Factor App

- **URL:** https://12factor.net/
- **Shared:** 2023-10-25, former tech lead: old (2011) but still the baseline for SaaS apps.

Takeaways:
- One codebase in version control, deployed to many environments. Every dependency declared explicitly.
- Config lives in the environment, not in code. Backing services (DB, queue, cache) are attached resources you can swap by config.
- Build, release and run are separate stages. Processes are stateless and keep nothing on local disk.
- Scale out with more processes. Start fast and shut down cleanly so processes can be replaced at any time.
- Keep dev, staging and production as alike as possible. Logs are an event stream written to stdout; the platform collects them.
- One-off admin tasks run as processes in the same environment and codebase.

Repo relevance: Kubernetes + Terraform already enforce most of this. The live points are config (owl [SECRETS-CONFIG]: hardcoded values should be Terraform variables), disposability (redelivery-safe handlers, [REDELIVERY-SAFETY], because a pod can die mid-message), and dev/prod parity (local seeds drift from accept; see MEMORY "Local stack & seeds").

---

## Microservices 101: transactional outbox and inbox (SoftwareMill)

- **URL:** https://softwaremill.com/microservices-101/ (published 2022-06-03)
- **Shared:** 2026-03-11, former tech lead, with a Repo example: ServiceC creates a company and broadcasts it to ServiceB and ServiceD; ServiceB then sends ServiceD a follow-up message, which can arrive before ServiceD has processed the company. A thread reply linked the follow-up to Repo PR #2113.

Takeaways:
- Publishing right after a DB commit can lose the message (crash between the two) or send one for a rolled-back change.
- **Outbox:** write the outgoing message to a table in the same transaction; a background worker publishes it. Publish-then-mark-sent is still not atomic, so duplicates remain possible. Several workers can share the table with row locks that skip locked rows.
- **Inbox:** acknowledge an incoming message only after the work is done, or persist it first, so a consumer crash does not drop it.
- At-least-once delivery means duplicates are normal. Consumers deduplicate by message key or make handling idempotent.
- Order is not guaranteed by brokers or HTTP. Increasing message ids let a consumer detect gaps and wait.
- Choose per flow: cheap tasks may only need ack-after-processing; expensive or order-sensitive work earns the inbox table.

Repo relevance: owl [PUBLISH-AFTER-COMMIT], [REDELIVERY-SAFETY] and ghost [EVENT-IDEMPOTENCY]. Repo's main answer to ordering is full-row messages with upsert-by-`updated_at` (`owl-review.md:94`), not sequence ids. ServiceD's `MessageSentOutboxDispatcher` is the one real outbox (see `SKILL.md` deltas). Pairs with `ms-dotnet-microservices.md` "Publishing atomically: outbox".

---

## Database replication and high availability

- **URL:** https://shobi.dev/blog/2023-01-14-database-replication
- **Shared:** 2023-10-21, former tech lead.

Takeaways:
- A read replica serves reads; all writes go to the primary, which frees primary capacity.
- Synchronous replication waits for replicas before commit: consistent but slower writes, worse across regions. Asynchronous commits first and copies later; it is the common cloud default.
- If the primary fails, replicas keep serving reads, and one can be promoted. Failover is not always automatic.
- Async replicas lag, so readers can see stale data. Monitor lag; a replica that drifts may need rebuilding.
- Route reads by freshness: "what I just did" goes to the primary, history and reports can go to a replica.
- Each replica costs a full instance. Replicas are handy for BI and heavy aggregation away from the primary.

Repo relevance: ServiceE and dbt-style reporting are the natural replica readers. The read-your-own-write rule is the same trap as reading a replicated copy in another service right after publishing an event (eventual consistency). Check with infra before assuming a service reads from a replica.

---

## OpenTelemetry baggage (SigNoz)

- **URL:** https://signoz.io/blog/otel-baggage/
- **Shared:** 2026-02-06, former tech lead: worth keeping in mind now that Repo has OTel instrumentation.

Takeaways:
- Baggage is key-value context that travels with a request through every service, carried in HTTP headers or gRPC metadata by instrumented clients.
- It is not a span attribute: backends do not store it unless you copy a value onto a span. Services can read it at run time.
- It removes "parameter drilling": a value set at the edge (a flag, a tenant) reaches deep services without every hop passing it on.
- It can drive run-time decisions, for example routing a request to a feature variant.
- It is attached to *every* outgoing call, including to third parties. Strip sensitive keys before external calls.
- The demo is Python; .NET's `System.Diagnostics` `Baggage` / `Activity` APIs are the equivalent (not covered by the article).

Repo relevance: useful for correlation (retailer, operation) across services. Two hard limits from the reviewer files: never put PII in it ([LOG-PII-BOUNDARY], no PII in URLs or headers), and never use it for authorization (ServiceC decides, [AUTHZ-OWNER]; bus or header data is not a permission source, [BUS-IS-NOT-RPC]). Shared OTel setup lives in `shared/Repo.Shared.Common/Extensions/OpenTelemetryExtensions.cs`.

---

## Also shared, not digested

- 2025-06-17, current tech lead: the `awesome-dotnet-tips` repository's `docs/testing` section (link in the Slack post). A link list, not an article; browse the testing folder when writing integration tests.
- 2023-10-23, former tech lead: ByteByteGo `system-design-101` repo. Broad visual primer from TCP to design patterns; too wide to digest, good for onboarding.
- 2024-09-05, former tech lead: "programming advice to my younger self" (mbuffett.com). General career advice, not architecture.
