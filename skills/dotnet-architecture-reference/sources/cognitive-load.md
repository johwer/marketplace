# Cognitive load is what matters

- **Source:** https://github.com/zakirullin/cognitive-load (README.md, the English edition)
- **Version read:** `main` at commit `d2d60d2` (2026-06-29). The README calls itself a living document, "last update: June 2026". Fetched 2026-10-17.
- **Kind:** an essay, not a book. About 440 lines, 20 short sections, no page numbers. Section names below are the README's own headings.
- **Licence:** Creative Commons Attribution 4.0 (CC BY 4.0), per the repo's `LICENSE` and the GitHub licence field. CC BY lets us share and adapt, including commercially, as long as we credit the source, link the licence and say that we changed it.
- **How to cite:** "Adapted from *Cognitive load is what matters*, github.com/zakirullin/cognitive-load, CC BY 4.0. Summarised and mapped to Repo; not the original text." Use that line whenever material from this file goes into a PR, doc or Slack post.
- **This file:** notes in our own words. Short quotes are marked "(README)". The images, the code samples and the guest comments at the end of the README are not reproduced.
- **How it reached Repo:** the former backend tech lead posted it in #knowledge-sharing on 2024-06-20 to the whole channel, saying everyone should read it. No thread discussion followed.

---

## Notes per section

### Introduction and definition
- Most "best practices" are taste dressed up as rules. The essay wants a yardstick that cannot be argued with: how confused a reader gets.
- Definition: "Cognitive load is how much a developer needs to think in order to complete a task." (README)
- Working memory holds about four chunks (variable values, control flow, call order). Past that, understanding falls off a cliff.
- We read code far more than we write it, and with LLM-generated code we now read even more. So the cost of a confusing design is paid many times.

### Types of cognitive load
- **Intrinsic:** the difficulty of the problem itself. You cannot remove it.
- **Extraneous:** the difficulty added by how the code is presented: clever tricks, the author's private habits, needless structure. You can remove it, and the essay is only about this kind.

### Complex conditionals
- A long boolean expression makes the reader hold every clause at once.
- Fix: pull sub-conditions into well-named local variables, so the `if` reads as a sentence.

### Nested ifs
- Each nesting level adds a precondition the reader must remember.
- Fix: guard clauses and early returns. After the guards, the reader only follows the happy path.

### Inheritance nightmare
- A change in a deep class chain means reading every ancestor, and then every descendant you might break.
- Prefer composition. The essay does not elaborate further.

### Too many small methods, classes or modules
- Rules like "methods under 15 lines" produce many **shallow** modules: the interface is large compared to what it does.
- A **deep** module has a small interface and a lot of hidden work (the classic example is Unix file I/O: five calls over a huge implementation).
- With many shallow modules you must learn each one *and* how they all interact. People think linearly, so jumping between tiny pieces is tiring.
- The author compares two 5k-line projects: 80 shallow classes was hard to return to after a break, 7 deep classes was easy.
- Important functions may be big; size can signal importance. This is not a plea for god objects.

### Responsible for one thing
- "One thing" is too vague to be useful, and it leads to factories of factories whose names cost more to learn than their bodies.
- The essay restates SRP as: a module answers to one user or stakeholder. If one bug brings complaints from two business owners, the boundary is wrong.
- Even that is open to many readings. Measure the cognitive load instead of arguing about the term.

### Too many shallow microservices
- The deep/shallow idea scales up. Many thin services become a distributed monolith: every requirement touches several services, and debugging spans the network.
- Example: a five-person team with 17 services, 10 months late, every change touching 4+ services.
- Boundaries are hard to get right early. Decide as late as is responsible, because a network boundary is hard to undo.
- A well-built modular monolith is often more flexible. Split when separate deployment is truly needed, for instance when the team grows.

### Feature-rich languages
- Every extra language feature is a choice the next reader must reconstruct ("why did they use *that*?").
- Limit the number of ways to do something. Features are fine when they do not overlap.

### Business logic and HTTP status codes
- Mapping business meanings onto HTTP codes (401 = expired token, 403 = no access, 418 = banned) forces frontend devs and QA to memorise a private table.
- Put a self-describing code in the response body instead (`jwt_has_expired`). Prefer readable strings over numeric statuses everywhere, including the database.
- Debates about 401 vs 403 are mostly mental-model arguments. Keep the split simple: user error vs server error.
- Side tip: "login" and "permissions" are easier words than "authentication" and "authorization".

### Abusing DRY
- Removing every repetition couples components that only look alike, across services and inside one module.
- Extracting too early bakes a guessed similarity into an abstraction that is then hard to change.
- A small copy can be cheaper than a dependency. "All your dependencies are your code." (README) You will debug their stack traces.

### Tight coupling with a framework
- Framework "magic" is a curriculum every newcomer must take before contributing.
- Keep business logic outside the framework and use the framework like a library. The essay is clear this is not a call to write everything yourself.

### Layered architecture
- The author used hexagonal/onion architecture for years. File counts doubled, glue code grew, and each requirement touched several layers.
- "Abstraction is supposed to hide complexity, here it just adds indirection." (README)
- Layers rarely deliver the promised storage swap. In the author's storage migration the adapter took hours; dealing with behaviour nobody had written down (event ordering) took 10 months. Hyrum's law: callers depend on every observable behaviour.
- Keep the fundamentals instead: dependency inversion, a single source of truth, information hiding, core logic testable without infrastructure.
- "Do not add layers of abstractions for the sake of an architecture." (README) Add an extension point when a practical need justifies it.

### Domain-driven design
- DDD's value is in the problem space: ubiquitous language, bounded contexts, event storming.
- Teams often reduce it to solution-space ceremony (folders, repositories, services), and each reader builds a different mental model of it.
- The essay suggests Team Topologies as a clearer way to split load across teams.

### Cognitive load in familiar projects
- "familiarity is not the same as simplicity" (README). Once you have learned a codebase's quirks it feels simple, which hides its cost from you.
- Mess builds up one small step at a time. Nothing simplifies code except deliberate effort.
- Ask newcomers to critique the code before they get used to it. If a new person is confused for more than roughly 40 minutes at a stretch, there is something to fix.
- Each project-specific mental model (a private blend of clean architecture, event-driven design and DDD) is extraneous load others must take on.

### Examples
- Boring architectures that last: a CRUD monolith on Postgres, small teams at large scale, systems such as Unix, Kubernetes, Redis.
- Judge an architecture by long-run effects, not by how good it feels now: is a bug easy to reproduce? Do people dare to change things? Can a newcomer ship quickly?
- Bring junior developers into architecture reviews; they find the heavy spots.

### Conclusion
- Cut every bit of load beyond what the problem itself demands.

---

## Repo mapping

Precedence still applies: the reviewer files and repo docs win over this essay. The essay is useful for explaining *why* several standing decisions exist, and for naming where Repo's own conventions add load.

| Principle (section) | Repo evidence (file:line or decision) | Verdict | Note |
|---|---|---|---|
| No layer without a job (Layered architecture) | 2025-10-08 team agreement: a controller may call a repository directly; "no law that you have to add a abstraction layer that makes no point" (`~/.claude/commands/ghost-review.md:645-651`, [REPO-PATTERN]) | **fits** | Same idea in Repo's words. ghost flags the pass-through service, not the direct repo call. |
| ... in the docs and code | `docs/CODING_STYLE_BACKEND.md:23` still says "Do not skip layers". 19 one-line `=> repository.X(...)` methods in `*/Services/*.cs`, e.g. `services/ServiceD/ServiceD.API/Services/EmailTemplateService.cs:24,119` | **partly** | The doc lags the decision. Some services are still partial pass-throughs; each such method is a hop with nothing to learn at the end of it. |
| Shallow modules / many small interfaces (Too many small modules) | `docs/CODING_STYLE_BACKEND.md:85` "Always use interface-based registration". About 266 of 337 interface files in `Interfaces/` folders under `services/` and `shared/` have at most one non-test implementation (grep heuristic, 2026-10-17) | **conflicts** | Most interfaces are one-to-one, there for DI and mocking. The essay would call many of them shallow. ghost's [SPECULATIVE-GENERALITY] already rejects "an interface + DI registration around something that is a plain helper" (`ghost-review.md:214-215`), but the style guide's blanket rule pushes the other way. Undecided; ask the tech lead before changing either. |
| Deep modules (Too many small modules) | `shared/Repo.Shared.Common/Extensions/WebApiExtensions.cs:14` `AddRepoWebApi<TDbContext>` wires JWT, logging, routing, Swagger and DbContext in one call. `ServiceC.API/Repository/Authorization/CachedAuthorizationRepository.cs` hides caching behind the existing repository interface | **fits** | Small interface, lots hidden. These are the shapes to copy. |
| Early returns over nesting (Nested ifs) | ghost 2026-05-13: "nested if statements like this is a big red flag" (`ghost-review.md:920`). "Never Nester" is in `docs/CODING_STYLE_FRONTEND.md:239` and `docs/CODING_STYLE_MOBILE.md:139` but not in `CODING_STYLE_BACKEND.md`. Nested examples: `services/ServiceA/ServiceA.API/Services/SearchDeviantService.cs:193-195`, `shared/Repo.Shared.Logging/Logging/SensitiveDataEnricher/SensitiveDataEnricher.cs:154` | **fits** (reviewer) / **partly** (backend doc) | The rule is enforced in review, not written down for the backend. |
| Composition over inheritance (Inheritance nightmare) | ServiceE request DTOs form a five-level chain: `ServiceAPerDiagnosesCodeRequest.cs:6` → `ServiceADaysReportRequest.cs:11` → `BaseCompanyReportRequest.cs:8` → `BaseCompanyRequest.cs:11` (adds `IValidatableObject`) → `BaseCompanyIdsRequest.cs:11` (all in `services/ServiceE/ServiceE.API/Models/DTOs/Requests/`). Also `Billing.API/Services/BillingProductService.cs:19` inherits a generic `BillingKleerSyncServiceBase<4 type args>` and overrides hooks (`:151-175`); `ServiceA.API/Services/BaseService.cs:7` | **partly** | The DTO chain is mostly data, which is cheap, but validation sits three levels up, so you read the whole chain to know what a request checks. The Billing template-method base is exactly the read-every-ancestor pattern the essay warns about. No decision exists on it either way. |
| Few, deep services (Too many shallow microservices) | 2025-01-02: organisation, user and auth merged into ServiceC because they called each other most; service-a, advisory and ServiceB stay separate (`owl-review.md:344`). Six service domains in `services/` | **fits** | Repo moved the way the essay recommends ("macroservices"). [BUS-IS-NOT-RPC] (`ghost-review.md:537`) also stops services from becoming a distributed monolith over the bus. |
| Self-describing result codes (Business logic and HTTP status codes) | `ApiResponse<T>` carries a string-named `ResponseResult` enum (`shared/Repo.Shared.Models/ResponseResult.cs:6`, `SUCCEEDED`, `NOT_FOUND`, `VALIDATION_ERROR`...) plus a human `reason`. Standard from 2024-11-26 ([RESPONSE-CONTRACT], `owl-review.md:246-256`) | **fits** / **partly** | The body says what happened, as the essay asks. But Repo still gives HTTP codes meaning: 404 also means "exists but you may not see it", failed login is 401. That is a deliberate security choice (don't reveal existence), which the essay does not weigh. |
| DRY with care (Abusing DRY) | [ONE-HOME-FOR-A-RULE] (`ghost-review.md:474`) and [REUSE-FIRST] (`:257`) push toward one place. ghost's fix for a duplicated company/customer path is explicitly *not* an `isCustomerLevel` flag that trades copies for branches | **fits** (rules) / **partly** (code) | Repo's DRY targets rules and security invariants, which is the "single source of truth" the essay keeps. The shared event library `shared/Repo.Shared.Messaging` is where the essay's coupling warning bites: one change there touches every service. |
| Framework outside the core (Tight coupling with a framework) | No MediatR or AutoMapper in any `.csproj` (0 hits, 2026-10-17); manual `MapFromDomain` (`~/.claude/skills/dotnet-backend-review/SKILL.md:113-115`) | **fits** / **partly** | Repo avoids magic libraries. But EF Core sits inside `*.Domain` (see `ms-architecting-modern-web-apps.md` mapping), so the core is not framework-free. The essay would accept that as long as rules stay testable; Repo's `Policies/` classes are. |
| Layers do not buy a storage swap; Hyrum's law (Layered architecture) | Repo does not aim to swap storage (web-apps mapping, persistence-ignorance row). Out-of-order events are handled by full-row messages and upsert-by-`updated_at` (`owl-review.md:94`) | **fits** | Repo already treats ordering as part of the contract instead of hoping an abstraction covers it. |
| Decide late, build for today (Too many shallow microservices) | [NECESSITY] runs first (`ghost-review.md:74`); [SPECULATIVE-GENERALITY] "generalise when the second consumer arrives" (`:203-212`) | **fits** | Same advice: no seam before the consumer exists. |
| Limit the number of choices (Feature-rich languages) | "backend, follow what we have" (2026-10-06, `ghost-review.md:651`). The 2026-06-01 #knowledge-sharing tip by the current tech lead on `switch` over polymorphic types with `[JsonPolymorphic]` | **partly** | The 2026-10-06 rule is a choice limiter. Newer C# features are welcomed when they cut code; nobody has said which ones are in or out. |
| Familiarity is not simplicity; unique mental models (Familiar projects) | The three reviewer lenses carry 111 bold tags (ghost 66, owl 32, the domain-data lens 13) plus dated standing decisions | **partly** | They make tacit rules explicit, which helps newcomers. They are also a project-specific vocabulary a new developer has to learn, which is the essay's "unique mental models". Keep tags as review aids, not as something a dev must memorise before the first PR. |
| DDD as problem space, not ceremony (Domain-driven design) | Entities are table-shaped, rules sit in `*.Domain/Policies`, no aggregate/specification ceremony (`ms-architecting-modern-web-apps.md` mapping, "Rich vs anemic") | **fits** | Repo uses the language and boundaries, not the folder rituals. |
| LLM output adds reading load (Introduction) | [COMMENT-NOISE] (`ghost-review.md:797`); repo `CLAUDE.md` "Write no comments in function bodies"; "max a few lines... If everything is important, nothing is" (2026-02-17, `ghost-review.md:901`) | **fits** | Repo's limits on AI comment and PR-text volume are cognitive-load rules by another name. |

---

## Questions this source helps answer

- *Do I need a service between this controller and the repository?* "Layered architecture" + the [REPO-PATTERN] row: only if the service hides something.
- *Should this one-implementation helper get an interface?* "Too many small modules" + the shallow-interfaces row. Today the style guide says yes and [SPECULATIVE-GENERALITY] says not for a plain helper; name the conflict, don't settle it alone.
- *Is this class too small, or too big?* Deep vs shallow: judge the interface against what it hides, not the line count.
- *Should I extract this shared base class / generic base service?* "Inheritance nightmare" + the Billing and ServiceE rows. Prefer composing a helper over a base class with override hooks.
- *Should these two similar code paths be merged?* "Abusing DRY" + [ONE-HOME-FOR-A-RULE]: merge rules and invariants, not code that only looks alike, and never with a mode flag.
- *Should this be a new microservice?* "Too many shallow microservices" + the 2025-01-02 ServiceC merge.
- *Which status code, and what goes in the body?* "Business logic and HTTP status codes" + [RESPONSE-CONTRACT]: the `result` enum carries meaning; the 404-for-hidden rule is a deliberate exception.
- *How do I review an AI-written PR for readability?* "Introduction", "Complex conditionals", "Nested ifs", plus [COMMENT-NOISE].
- *How do we know if the codebase is getting harder?* "Examples" and "Familiar projects": time-to-first-PR, newcomer confusion, fear of touching code. Ask the newest dev.
