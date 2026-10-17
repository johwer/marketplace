# Placement test

Eight questions, two per level, easiest first. Ask one at a time. Grade full (1), partial (½) or missing (0).

Scoring: a level counts as **reached** when both its questions score at least 1.5 together **and** every lower level is reached. Stop early only if the user asks; otherwise ask all eight, because a higher-level answer can show knowledge that a lower one missed.

---

**Q1 (L1.1, L1.3)** The employee page asks for one service-a report: `GET api/service-a/v1/service-areport/{id}`. Walk it from the request to the database and back. Where is it decided whether this user may see it?
- Key points: controller (`ServiceAReportController`) → service → repository → Postgres, and back as a DTO inside `ApiResponse`. The controller asks ServiceC (`CanDoActionOnUser`) before returning, because ServiceC owns authorization; the service does not decide permissions locally.
- Anchor: `services/ServiceA/ServiceA.API/Controllers/ServiceAReportController.cs:41,70`.

**Q2 (L1.2, L1.4)** Why don't we return the EF entity `ServiceAReport` straight from the controller? And what status should the API give when the user isn't allowed to see it?
- Key points: the DTO is the contract with the frontend (a column rename doesn't break the UI); only chosen fields leave (no personal data or internal flags); request DTOs stop over-posting; navigation properties would leak and cycle. Not allowed → 403 (or 404 when existence itself must not leak) inside the envelope.
- Anchor: `lift-the-gaze/references/layers.md` "Why DTOs", `shared/Repo.Shared.Models/ApiResponse.cs`.

**Q3 (L2.1, L2.2)** A new endpoint lists all service-as for a company to show in a table. Name two things you'd check in its EF query.
- Key points (any two for full): `AsNoTracking` for a read; `Select` into the DTO instead of loading full entities; no repository or ServiceC call per row (N+1) — batch; filter in SQL before `ToListAsync`; `AsSplitQuery` with several collection `Include`s; filter `DeletedAt` if the table soft-deletes; pagination.
- Anchor: `dotnet-backend-review` §1.

**Q4 (L2.4, L2.5)** ServiceC creates a company and publishes `CompanyEvent`; ServiceA keeps a copy. (a) In ServiceC, publish before or after `SaveChanges`, and why? (b) ServiceA receives the same event twice, or an old one after a new one. What must its handler do?
- Key points: (a) after the commit, otherwise consumers can see a company that was rolled back; await the publish. (b) idempotent: upsert, and only apply if the incoming `UpdatedAt` is newer (full-row event), so duplicates and reordering don't matter; rethrow on error so Rebus retries.
- Anchor: `services/ServiceC/ServiceC.API/Services/CompanyService.cs:164`, `services/ServiceA/ServiceA.Domain/Repository/UserRepository.cs:177` (`IsNewerThan`).

**Q5 (L3.1)** A new feature should only exist for customers who bought a particular product. Where do you put the gate: a PostHog flag, the service contract, or an ServiceC permission? What code do you avoid writing because of where you put it?
- Key points: the service contract is the switch ("the contract is the switch", PROJ-3847, 2026-10-12); a flag is temporary rollout, not entitlement; ServiceC answers "may this user", not "has the customer bought it". Gating at the contract means no per-retailer branches and no null handling for customers without it in the layers below. Mention that a frontend gate alone is not security.
- Anchor: `shared/Repo.Shared.Models/ServiceContracts/ServiceContractExtensions.cs`, ghost [CONTRACT-IS-THE-SWITCH].

**Q6 (L3.3, L3.6)** Two requests try to create the same subscription for the same user at the same moment. How do you stop a duplicate? And what changes if the code runs in a worker with two pods?
- Key points: a unique index as the final guard, returning 409 on conflict; serialise with `pg_advisory_xact_lock(hashtext(key))` inside the transaction when a check-then-insert must be atomic; `UpdatedAt` concurrency token for updates. Two pods: in-memory locks don't help — use the DB lock, a claim row, or keep one replica on purpose.
- Anchor: `services/ServiceA/ServiceA.Domain/Repository/UserRepository.cs:154`, PROJ-4405 (PR #4056), `dotnet-backend-review` §6.

**Q7 (L4.1, L4.2)** Users say the dashboard is slow. What do you do before proposing any change?
- Key points: measure first — Elastic: p95 per endpoint for service-a-api (the dashboard calls are ~2 s on accept), then one trace to see where time goes (SQL, ServiceC calls, N+1); accept shows where time goes, not prod speed, so ask for prod numbers if scale matters. Classify (data vs logic, read-heavy) before choosing a fix; don't jump to caching or a new architecture.
- Anchor: `lift-the-gaze` Step 0.5 "Measure, don't guess".

**Q8 (L4.3, L4.4)** The textbook says a controller must never call a repository directly. In Repo it sometimes does. Is that a mistake? How would you find out?
- Key points: not a mistake — team agreement 2025-10-08 (current tech lead): a service only when it does something; no empty pass-through layer. `CODING_STYLE_BACKEND.md:23` still says "do not skip layers" and lags the agreement (open question to the tech lead). Finding out: standing decisions in ghost-review / backend-decisions, then `repo-vs-textbook.md`.
- Anchor: `services/ServiceA/ServiceA.API/Controllers/CountController.cs`, `repo-vs-textbook.md` "Layers / skipping layers".
