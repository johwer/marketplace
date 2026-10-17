---
context: fork
---

# Ghost Review — Pre-emptive Backend Code Review

Simulate the current backend tech lead's review style against a PR or ticket before he sees it. Flags must-fix issues and surfaces the clarifying questions he would ask, so they're resolved before the review cycle.

$ARGUMENTS

## Who is the tech lead?

The current tech lead is a senior backend reviewer who:
- Asks architecture-first questions before accepting a design
- Expects developers to apply architectural judgment to the ticket itself: a mechanism relayed from product/customer (even "TT wants X") is a *suggestion, not a spec* — push back and model it the way the system actually works ("my expectation is that we apply judgment about that before implementation")
- Flags security issues (auth ordering, multi-tenancy, privilege escalation) as must-fix
- Leaves clarifying questions when semantics are ambiguous — he won't approve until they're answered
- Is consistent about patterns he's flagged before: he will ask again
- Has a 0% resolution rate on "missing integration test" flags (0/9 in scraped history) — the team tends not to add them, so he keeps asking
- Prefers code that **fails loud** (throw) over silent defaulting, null-coalescing fallbacks, `continue`, or returning stale data on failure
- Pushes for **enums/domain constants** over hardcoded strings, and dislikes fully-qualified namespaces (FQDN) in code

His review style: precise, code-specific, not generic. He cites the exact file and line pattern. He doesn't nitpick style (linters handle that) but he does care about naming when it violates REST or DTO conventions.

> **Data backing these patterns** (from `pr-learnings.json`, scraped review history): **1,103 review comments** by the tech lead across ~590 PRs he reviewed (106 must-fix). Categories: pattern (118), architecture (109), naming (59), api-contract (58), types (51), missing-test (51), error-handling (47), security (40, highest must-fix rate), performance (17), plus many clarifying questions. His must-fix verdicts concentrate in **security, error-handling, architecture, and EF/persistence modeling**. He frequently flags: layering/Unit-of-Work violations, AWS credential/region hardcoding, token-authority & header spoofing, catch-and-log-only, build warnings, commented-out code, and tests that don't assert real logic.
>
> **Second mining pass (2026-05-25 → 2026-10-13):** 664 GitHub comments by the tech lead on 141 PRs (≈29 of them replies to review on his own PRs, kept only where they state a decision), plus dated Slack/Jira decisions through 2026-10-15 (see Mode 2 "Standing decisions"). What moved since the first pass: his weight shifted from per-endpoint security toward **altitude** — products are data not code, the service contract is the switch, one home per rule, rollout-safe schema changes, the SignedIn→Nova migrators — and toward a high bar on AI-generated comment volume and PR scope. New tags from this pass: PRODUCT-IS-DATA, CONTRACT-IS-THE-SWITCH, ONE-HOME-FOR-A-RULE, UNREACHABLE-PERMISSION, EXPAND-CONTRACT, MIGRATOR-PARITY, EVENT-IDEMPOTENCY, DATA-FIX-ROUTE, PRODUCER-OWNS-DERIVATION, PAGE-AUTHZ-CONTEXT, PR-SCOPE, COMMENT-NOISE.
>
> **Identity:** people are named by role only, never by name or handle. To mine again, ask the user for the GitHub login and Slack user; they are not stored here. A spot check on 2026-10-17 covered PRs from 2026-10-13 to 2026-10-17: 5 PRs, one decision kept (#3985).
>
> **Slack pass (full walk of his messages, 2025-05-06 → 2026-10-15):** Slack: ~5,060 messages scanned, ~220 kept, date range 2025-05-06 → 2026-10-15. There are no messages before 2025-05. About 85% was noise: changelogs, standups, incidents, social posts, one-liners. Kept items became dated Mode 2 "Standing decisions" and "Slack sharpening" notes under existing tags. New tags from this pass: BUS-IS-NOT-RPC, BAD-INPUT-IS-4XX, CONTRACT-ENCODES-RULES, IDENTIFIER-SEMANTICS, LOG-PII-BOUNDARY, NO-STORED-PROC, CACHE-INVALIDATION, CAPABILITY-IS-NOT-ELIGIBILITY. Three items revise earlier patterns:
> - the 2026-03-05 [PRIVILEGE-SCOPE] carve-out;
> - the 2025-10-08 controller→repository agreement in [REPO-PATTERN];
> - the user-initiated-PUT scope of [UPSERT-PREFS].

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

Skip non-backend files for this review: ignore `*.tsx`, `*.ts`, `*.snap`, `*.json`, `*.md`, `*.sql` seed files, `*.Designer.cs`, `*ModelSnapshot.cs`.

Focus on: `*Controller.cs`, `*Repository.cs`, `*Service.cs`, `*Handler.cs`, `*Worker.cs`, `*.Domain/**`, `*Mapper.cs`, `*Request.cs`, `*Response.cs`, `*.cs` in shared/

### Step 2 — PR description pre-emption scan

Extract what the PR description explicitly acknowledges. These are already "on the table" — the tech lead may still comment but the team has a prepared answer. List them:

```
### Already pre-empted in description:
- [list of acknowledged decisions]
```

### Step 3 — Apply the checklist

Run each check below against the actual diff/patches. Only flag a check if the code *actually shows the pattern* — not hypothetically. Cite exact file and line context from the patch.

---

#### RUN THIS FIRST — [NECESSITY] Does the change need to exist?

Every other check below asks whether the code is built correctly. This one asks whether it should
be built. Run it before reading a single line of implementation, because if it fires, the rest of
the review is wasted effort on both sides.

The tech lead raises this as a **blocking** finding, and his characterisation above already says why:
a mechanism relayed from product, from a customer, or **from the ticket itself** is a *suggestion,
not a spec*. A ticket that names its own mechanism has not thereby justified it.

For every capability the diff adds, answer all four:

1. **What already provides this?** Search for the capability, not the name. An endpoint, a role, a
   flag, an existing scope combination. "There is no X" is only true after grepping for what X does.
2. **Is the constraint the ticket cites a constraint, or a convention?** A DB check constraint, an
   enum, a type signature are constraints. A seed comment, a naming pattern, an existing row's
   shape, a doc line are **conventions** — they explain a past choice and can be changed. Read the
   artefact that enforces it; if nothing enforces it, the ticket is describing a habit.
3. **Is this a config job rather than a code job?** If the capability can be reached by seeding,
   assigning, or configuring what already exists, the code is not the smaller change however clean
   it is.
4. **Does it change a shared authorization, permission or domain rule?** If yes, that needs
   prealignment before implementation, not review after. Flag it as MUST-FIX regardless of quality.

Write the finding as: *what the change adds → what already provides it → the cheaper route*. Do not
soften it into a suggestion; a correct implementation of an unnecessary change still gets closed.

**New mechanism vs existing one (standing decision 2026-10-16).** "Always be careful about building
a mechanism we dont have." Careful means "something new needs taste, judgment and consensus.
Something existing is just to go hard." So the order is: use what exists (an API, a config screen,
a manual step) → a migration only when needed to avoid data loss → a new mechanism (a reconciler,
a backfill tool, a new endpoint) only with prior consensus. With one live prod customer, "manual
turning stuff on is reasonable" — a per-company manual switch beats automation nobody asked for.
(PROJ-4061: Nova-native companies get a new service via the existing `PUT company/{id}/products`,
not a backfill or a new rollout mechanism.)

> **The incident this came from (PROJ-3952, 2026-09-21).** A narrow ServiceC endpoint was designed,
> built, unit- and integration-tested against real Postgres, passed 20 CI checks, and was reviewed
> favourably by the domain lens — then closed by the tech lead: *"This is a huge architectural
> intrusion into the role and permission system without any prealignment or discussion afaik.
> Please do not do that again."* The capability already existed: `RoleScopeRules` forbids only
> **customer-level** roles at Retailer scope, and the nurse roles were customer-owned because a
> **seed comment** said they were "retailer-wide rather than tied to a single company" — a
> rationale, not a constraint (`ck_roles_owner_xor` was satisfied either way). A company-level role
> carrying the same platform action could always be assigned at retailer scope with the existing
> endpoint. Check 2 would have caught it by reading the constraint; check 3 by asking whether it was
> config. All three pre-emptive lenses passed the PR, because all three asked only whether it was
> built well. It was.

---

#### MUST-FIX patterns (the tech lead blocks approval on these)

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

**Carve-out since 2026-03-05 (Slack, announced to the whole channel):** a `UserPermission` *may* now
grant `CompanyAction`s on **the company the targeted user belongs to**. The cases he gave were
reads: service-a templates for filters, and service-e benchmarks via tag access. "That simplification
just didnt work out." Do not flag that shape on its own. Still flag role management, user creation
("You can't create a user as a userpermission. You need company access", 2026-03-06) and other
company-wide writes reached from a user-level permission. Also: an action on a person's data (e.g. a
health case) is a `UserAction` even when granted across a whole company: "the action is on the
user" (2025-11-03). A widget needs the permission for what it *does*: managing a case, not just
reading it (2026-03-02).

**[GATE-NOT-EXCLUSIVE] A new permission that gates nothing only it grants**
When a PR adds a Permission and then gates an endpoint on an *action*, check how many
permissions grant that action: `grep -n "UserAction.<Action>" services/ServiceC/ServiceC.Domain/Permissions/DefaultPermissionsMappings.cs`.
If several everyday permissions grant it, the new permission is decoration — anyone holding
`ViewServiceA`, `ViewCase` or `ManageUserProfile` passes the same gate.

Flag it, and name the fix: a purpose-made action granted only by the new permission. An Action is
a cheap change (mapping files only, no assignability map, no seed, derived at runtime), so "it
would be more work" is not a defence.

Then check the other half, because narrowing the gate usually breaks it: does the new permission
still satisfy the *per-target* check further down? If it grants only the new action, the caller
passes the gate and has every result dropped — they can search and see nothing. That empty result
is indistinguishable from "no such record", so it fails silently. The permission must grant both.

Concrete: PROJ-3184 gated on `UserRead` (≈8 grantors), narrowed to `UserSearchBySsn` granted only
by `CustomerPermission.MedicalAdvisor`, then had to add `UserRead` to that permission too.

**And then deleted the new action entirely**, which is the part worth learning. The shipped gate is
`UserAction.UserReadConfidential`, an action that already existed, because
`UserSearchRepository.BuildSearchConditions` already refuses to match on SSN unless the performer
holds it. The bespoke action was an exception to a rule the codebase already enforced. So run this
pattern *after* the check below, not before it — exclusivity is worth buying only once you have
confirmed nothing already governs the data.

**[SILENT-SUPERUSER-INHERIT] A new action silently inherited by CustomerSupport**
`CustomerPermission.CustomerSupport` is mapped in a blanket loop over
`Enum.GetValues<UserAction>()` minus a two-member exclusion list
(`DefaultPermissionsMappings.cs`, near the CustomerSupport block). So **every new `UserAction`
is granted to customer support the moment it enters the enum** — no mapping line, no decision,
no review.

Two things follow, and both are worth flagging on any PR adding a `UserAction`:

Never write "granted only by X" about a new action without checking that loop. It is true of the
lines the PR adds and false in practice. The honest claim is "exclusive against everyday view
permissions", which is usually the point being made anyway.

Ask whether support *should* reach the new capability. Usually yes, and usually harmless because
support already holds broader tools. But the inheritance is a silence rather than a decision, so
for anything support should not reach, the exclusion list is where that gets said — and nobody
will notice it was not.

Concrete: PROJ-3184 added `UserSearchBySsn` for a nurse-only search and customer support acquired
it automatically. Correct outcome, wrong description, and the PR claimed exclusivity it did not have.

**[SPECULATIVE-GENERALITY] A name or abstraction built for a second consumer that does not exist**
The mirror of REUSE-FIRST, and he will push back on it just as hard. Before widening a name or
extracting an abstraction "so the sibling ticket can use it too", confirm the sibling still needs
it: check its branch, not the plan. A reuse argument built on a design that has since been
reverted is worse than no argument, because it bakes a guess into a name.

Concrete: PROJ-3184 modelled a two-key lookup contract, complete with an unimplemented branch
answering 501, for a sibling ticket that then shipped its lookup on a different service entirely
and later reverted it. The seam was removed as unused surface. Specific names age better than
hopefully-general ones — generalise when the second consumer arrives, with the consumer in hand.

The same goes for **handling a scenario that does not happen in practice**, and for an interface
+ DI registration around something that is a plain helper. On #3369 (PROJ-3522) a source-deletion
sweep for customers deleted mid-migration got: *"Deletion of a customer we want to migrate in
signedin mid migration isnt really a thing... we should probably roll back that entire
complexity."* On #3167 and #2909 (PROJ-2798) he questioned a per-request DI class and an
interface for a one-off seeder; on #3781 he called an extra layer "unnecessary abstractions".
Ask "does this case actually occur?" before building for it, and expect AI-proposed robustness to
be the usual source.

**[DATA-ALREADY-GOVERNED] A new gate designed around a field that already has one**
Before designing any gate for access to a *field* — identity number, date of birth, salary, a
medical note — grep how that field is already treated in the code that reads it today, not how the
permission model is organised:

```
grep -rn "<Field>" services/<Svc> --include='*.cs' | grep -iE "permission|action|canuser|confidential|mask"
```

Read the search and read layers, and read the *conditions*, not just the projections — the rule is
often "we will not match on it" rather than "we will not return it", and that is easy to miss when
you are reasoning about responses. If an existing right already governs the field, reuse it. A new
action gating the same data is an exception to an existing rule, and it will be asked to justify
itself against that rule sooner or later.

Concrete: PROJ-3184 spent four gate designs and two enum renames on a nurse SSN lookup before
finding `UserSearchRepository.BuildSearchConditions`, one grep away, which already required
`UserReadConfidential` to match on SSN at all. Everything bespoke was then deleted.

**[DEFER-OWN-MESS] Cleanup of a duplication the PR itself introduced, pushed to a follow-up ticket**
He accepts deferring cleanup you inherited. He does not accept deferring cleanup you created:
*"You cant add stuff and then defer cleanup to a future PR imo?"* The line is ownership, not size
and not risk.

So when a PR adds a second copy of something, check `git log -S` or the merge base to see whether
the duplication is older than the branch. If it is not, the follow-up ticket is not a plan, it is a
handoff of your own mess — and the arguments that feel strongest for deferring ("it touches another
team's path", "it changes nothing functional", "it would block the sibling ticket") are exactly the
arguments that apply equally well to never doing it.

Concrete: PROJ-3184 added a caller-scope resolver that was `GlobalSearchService.GetAuthorizedCustomerIdsAsync`
minus the retailer resolution, and opened PROJ-3829 to merge them later. Reviewer refused; merging
them in the PR removed 89 net lines and the follow-up ticket was closed unneeded.

**[REUSE-FIRST] A new action or class where an existing one fits**
He asks "could this reuse X?" before accepting anything new. Before adding an Action, enum member,
helper or class, search for an existing one and either use it or state in the PR why it does not
fit. A defensible answer names the mismatch: e.g. the 87 `UserAction` members are all "read this
attribute of a person you already identified", whereas a lookup by an external key is "find a
person you cannot yet name" — a different capability, so none fit.

Also check the inverse: a class with ONE caller where that caller is a pure pass-through should be
inlined. And logic that duplicates an existing service's helper should say so and pick a direction.

Reuse applies to **mechanisms and flags, not just classes** (standing decision 2026-10-12: "we
don't invent a new way"). Before a new flag, toggle, pipeline, link scheme or provisioning path,
name the existing one and say why it does not fit.

**[JUSTIFICATION-VS-MECHANISM] A comment or commit message that the code does not support**
His sharpest reviews read the collaborator, not the comment. For any defensive mechanism —
a probe, a retry, a swallow, a sentinel — open the thing it calls and confirm the failure it
defends against can actually occur:
- Does the adapter already catch and return false, so the exception you handle never escapes?
- Does the call return early on the sentinel you pass, so the cost you are equalising differs anyway?
If the justification is false, the mechanism goes — do not rewrite the comment to fit.

Concrete: PROJ-3184 carried a `Guid.Empty` probe justified first on a status-code asymmetry that
could not occur (the HTTP adapter catches and returns false) and then on latency (the check returns
after one lookup miss for `Guid.Empty` but continues for a real hit). Both false; it was defended
twice before being deleted.

**[VACUOUS-TEST] A test whose inputs cannot exercise what it claims**
For any test named after a guard, check the inputs could actually trigger it. Read the assertion
against the property: if the inputs cannot produce the failure, the test is green for the wrong
reason. Either construct the real case or delete the test and its claim.

The operational check, because reading is not enough — **name the input that would make it fail,
and confirm the fixture contains it.** For a "does not collide" test that means: is there a stored
value that is a candidate for *both* searches? If every seeded row can only ever match one of them,
nothing is being guarded. Equivalently: break the implementation on purpose and watch the test go
red before you trust it green.

He caught this twice on the same ticket, the second time on the *fix* for the first. PROJ-3184's
century test first used two different birth dates 90 years apart, which could never collide. The
replacement seeded two 12-digit rows, which also cannot collide, because both carry their century.
The real case is a row stored as ten digits: it carries no century, so it is a candidate for both
`19…` and `20…` and comes back for each. Two rounds of review to notice that the fixture, not the
assertion, was doing the lying.

**[REDUNDANT-RESPONSE-FIELD] A field constant across every row**
A response field set from the request is the caller's own input echoed back. Flag it. Do not accept
"take it from the row instead" without checking what the row holds — if storage is unnormalised,
the stored value leaks which internal format matched.

**[MULTI-TENANCY] Missing cross-tenant validation**
Look for:
- Service/handler methods that accept `companyId` from request body/params without validating it belongs to the `customerId` from the JWT
- Event handlers that use `roleData.CompanyId` or similar payload fields instead of `message.CompanyId`
- Repository queries that filter by `companyId` without also filtering by `customerId`
- Role-assignment / entity-binding code that does not validate the **roles (or referenced entities) actually belong to the validated company** — e.g. assigning a role by ID without confirming that role is owned by the caller's company (flagged as a "large security issue" in `RoleAssignmentRepository.cs`)
- Endpoints missing **customer scoping** needed to support cross-tenant users (e.g. `UserWidgetController`)
- A **role check standing in for tenant authorization**: it checks the role "not if you are actually authorized on a specific company" (Slack 2025-09-19, called cross-tenant exposure)
- **Write endpoints keyed by a guessable child id** with no owner check: "can I (if i know the ID) upload documents into any health case?" (Slack 2025-10-27)
- A child entity carrying its own `company_id` when the user replica already has it: "only trust the user's company id" (Slack 2025-12-19)
Nuance: "Cross tenant role assignments are not wrong" in themselves. Support staff and the partner's professionals work that way (Slack 2026-09-01). Flag *unvalidated* cross-tenant access, not every cross-tenant assignment.

**[S2S-VS-USER-API] User-facing API reused as service-to-service**
Look for a user-facing controller/endpoint (or `AuthorizationAdapter` built for user-context auth) being called or reused as a service-to-service (S2S) path. The authorization models differ — user APIs assume a JWT user context; S2S has none. Reusing one for the other violates the Repo bus-driven pattern. Flag if a user-auth endpoint is being consumed internally as if it were an S2S contract.
Slack sharpening: user-facing endpoints carry "business rules… that make sense from a logged in
user's perspective but not service2service" (2026-01-29). Only the `*.Sync` APIs accept both user and
service tokens (2026-02-02). Don't add fields or branches to a user-facing endpoint for a one-off
migration script (2026-02-27). The reverse also holds: when an external consumer already depends on
a user-facing API, changing it is "mostly our responsibility… Or atleast inform about it"
(2026-05-19). Ask whether the PR changes an endpoint an external migration or integration calls.

**[AUTHORIZED-FEATURES-MISUSE] Field added to `authorizedFeatures` for an external/non-FE consumer**
`customer/{id}/authorizedFeatures` models **Repo's own frontend viewport** (which UI/nav a signed-in user sees). Do NOT add a boolean there for an external system (Seru/Leo, other services) or for a permission the Repo FE doesn't consume — it's noise and doesn't scale. External systems read a user's grants via the existing `authorization/.../action/{action}` endpoints. Flag any new `authorizedFeatures` field whose only consumer is external or non-UI. (PROJ-3183.) Direction since then: he wants `authorizedFeatures` dropped entirely (#3309, PROJ-3452: "can we drop authorizedFeatures entirely now? We need to ping TT before that"), and platform flags there are known to be resolved from a different assignment set than the API gate (#3222, PROJ-3367 → PROJ-3365). So any **new** field there is a MUST-FIX, not a question.
Slack sharpening: it is deprecated in favour of `/features`, which exposes the authorized actions
"so the client can do its own decision" (2026-08-17). Two rules apply to the flags that remain. One
feature, one flag: a flag gating two features is wrong because "you might have access to one but not
the other" (2026-05-25). A flag reads the dedicated action it is about, never a derivation from
other actions (2026-03-18, pushback on a `HasSupport` built from read actions).

**[PERMISSION-PLACEMENT] Permission modeled at the wrong scope, or filed under a contract its holders do not hold**
Three checks.

(1) A company-level capability must be a `CompanyPermission`/`CompanyAction`, not `UserPermission`/`UserAction` — mirror the closest existing feature (e.g. `TTViewInsightsHub` → `InsightsHubRead` for analytics).

(2) Don't gate a permission under a `ServiceContractType` it merely *resembles by name* (e.g. parking a "Reporting" permission under `ServiceE`) — `ServiceContractType` reflects the **contract that entitles** it. If it's universal to a retailer, put it in the `AlwaysOn` baseline instead; only use a contract entry if a real contract gates it. (PROJ-3183.)

(3) **Assignability is a trust boundary, not a taxonomy — this is the security check.** The contract you file a permission under decides **who may hand it out**, because `CustomerRoleService` validates every assignment against the `AssignableCustomer`/`AssignableUser` set that `ServicePermissionMap.Compose` returns. So the question is never "which contract is this about" but **"is this contract held only by the people who should be able to grant it?"**

Resolve it against the seed, not the name: `grep -n "<ContractType>" scripts/database-init/seed-service-c/seed-0-products.sql` and look at which product carries it. A contract on the `Default` product is held by ordinary customers, so a permission filed there is **self-grantable by any customer admin whose company activated that service**. A contract that appears only on `Unlocked Service` is internal. Internal-staff capabilities belong on the internal contract, which today means `SupportGrant`.

Concrete: PROJ-3184 filed `CustomerPermission.MedicalAdvisor` — a nurse capability for Repo's own staff — under `MedicalAdvisoryCallback`, the contract customers buy to *receive* callbacks. Name matched, trust boundary inverted. Once the gate moved to `UserReadConfidential`, that made confidential read of identity numbers self-grantable inside any customer that had the callback service. Reviewer caught it; the fix was moving it into `SupportGrant`.

**Do not repeat the claim this block used to carry, that `ServicePermissionMap` is a test-only consistency layer with `ProductMap` as the live path.** `ProductMap.cs` was deleted by PROJ-2912 and `ServicePermissionMap.Compose` has one live caller, `AssignablePermissionProvider`, injected into `UserService`, `RoleService` and `DefaultRoles`. That stale sentence sat inside this very pattern and is the reason PROJ-3184 read a placement bug as cosmetic — the rule was right and its own footnote repealed it. Re-verify a rule's stated stakes whenever you trust the rule.

(4) **Slack rules on where an action lives:**
- Code gates on the *Action*. Which permission grants it is decided in the ActionMap (2026-01-19).
- A permission follows where the thing is attached ("A company? Use a company action? A customer? customer action? A retailer? retailer action?", 2025-10-30).
- Don't reuse a broad admin permission for a domain admin. Define a dedicated one.
- No domain-specific confidential actions: identity-number reads go through `UserReadConfidential`, not a per-service `*ReadConfidential` (2026-03-05).
- Manager and employee roles sit on the company, admin roles on the customer (2026-10-07).
- "Be abit mindful about creating/modifying permissions for TT. Actions are fine" (2026-03-25), because what TT permissions mean was agreed with product and the retailer.
- An action's name must match what it gates. If it gates something else, rename it (2026-03-27).

**[UNIT-OF-WORK] SaveChangesAsync inside a repository, or called multiple times**
Look for `SaveChangesAsync()` / `SaveChanges()` called inside a `*Repository.cs` method. Repositories must not commit — the Unit of Work boundary belongs at the service/handler layer. He blocks on this. Also flag **more than one `SaveChangesAsync` in a single operation** ("please do not do two SaveChangesAsync here — ideally call it once for the entire update") — multiple saves break atomicity.

**[SCOPE-DISPOSAL] Disposed DI scope or service used after disposal**
Look for a scoped service or `IServiceScope` captured and then used after the `using`/scope has ended (e.g. stored on a field, passed to a continuation, or awaited after disposal). Causes a resource leak / `ObjectDisposedException`. Also watch for per-item DB calls inside a loop — he flags N+1 round-trips as must-fix when the volume is unbounded.

**[SETVALUES-IMMUTABLE] EF Core SetValues() on audited entities**
Look for `entry.CurrentValues.SetValues(...)` or `dbSet.SetValues(...)` on entities that have fields like `InsertedAt`, `CreatedAt`, `UserId`, `CreatedBy`. SetValues() overwrites everything including audit fields.

**[DEPLOY-PIPELINE] New containerized service/worker without _deploy.yml update**
Look for new `*.Worker` or `*.Api` projects (new `.csproj` files, new `Dockerfile`) that aren't matched by a corresponding image push step in `.github/workflows/_deploy.yml`. Only flag if there's a new project being added.
Slack sharpening:
- A new appsetting goes in **three places**: `appsettings.json`, `docker-compose.yml` and `infra/k8s`. A config-format change updates the k8s configmap (2025-11-24, 2025-12-01).
- A new project also goes in the solution file and the Dockerfile.
- Terraform: "dont leave undestroyable terraform resources on a branch since they block terraform apply on main". Apply-on-merge means split PRs: secrets first, then the workload (2026-06-26).

**[HTML-ENCODING] Unencoded user-controlled values in email templates**
Look for string interpolation or `Replace()` calls in email template generation where the substituted value comes from user-controlled data (Department name, user name, company name). Flag if `System.Net.WebUtility.HtmlEncode()` is not applied.
Wider than email: storing or rendering raw HTML anywhere (e.g. an activity log) is "a XSS entrypoint… we need to get rid of it" (Slack 2025-07-08). HTML is also off the upload allow-list because it "can include javascript" (2026-05).

**[DTO-NAMING] DTO missing Request/Response suffix**
Look for DTOs returned from or accepted by controllers that don't carry a `Request`/`Response` suffix, or response models reused as request bodies (which forces awkward field assignments). He treats the suffix convention as must-fix, not a nitpick.
Slack sharpening:
- Use the C# `required` keyword, not `[Required]` ("compile time guarantees… the keyword is enough", 2025-11-05).
- Annotate `[ProducesResponseType]` so Swagger documents the success shape (2025-11-13).
- "Never return a domain object from a controller" (2025-10-08), and don't pass the whole domain model into the API.
- Return only what the design displays (2025-11-14).
- See [CONTRACT-ENCODES-RULES] for splitting create/update and request/stored enums.

**[MIGRATION-BY-HAND] EF migration files edited manually**
Look for hand-edits to generated migration files (`*_Migration.cs`, `*Designer.cs`, `*ModelSnapshot.cs`) instead of regenerating via `dotnet ef migrations remove` + re-add. Also flag data-correction needs that should ship as a migration (e.g. "add a migration to lowercase all existing tokens") rather than being assumed. (Note: a migration-guard hook also warns on this.) If a migration in this PR drops something an earlier migration *in the same unshipped PR* added, fold them (owl's #2946 finding, same rule).

**[EF-MODELING] Incorrect entity / migration modeling**
He is strict about the data model. Flag:
- Migrations with only a PK constraint where a **foreign-key relationship** is missing ("missing FK relationship in migration")
- Columns stored as `int` that represent an enum ("No ints plz! Fix all enums")
- Wrong numeric types (`decimal` where a count should be `int`)
- Missing `ValueGeneratedNever()` / value-generation config on PKs that are assigned, not generated
- Compound-key tables without a **unique index** on the composite key to prevent duplicate rows

Slack sharpening (2025-05 → 2026-04):
- **`inserted_at` on every table**, relation tables included. `modified_at` everywhere except immutable data. Keep the `inserted_at`/`modified_at` naming (2025-08-19).
- **No int ids**, and no legacy-id mapping columns in Nova DBs ("Any mapping between old ids will only be during a migration", 2025-11-26).
- A **replicated owner id is a non-null FK**. Out-of-order events are handled by replaying the message, not by making the column nullable (2025-12-01).
- **Don't copy an owner id onto a child** when the parent's replica already has it ("join in the company id from the user", 2025-09-15).
- **Store the id, not a display name.** Resolve names from the local user replica (2026-03-09).
- **State by row existence, not a bool** next to another bool. That combination produced "5 states with 2 undefined" (2025-05-19).
- **One concurrency token: `UpdatedAt`.** "We should not have two concurrency tokens regardless" (2026-04-01).
- **Removing an enum value that is stored in a DB needs "a tiny migration that removes it from all DBs"** (2026-03-23). Deleting an enum "without a proper DB migration" broke accept (2026-08-11).
- Missing `ValueGeneratedNever()` on child Guids set in C# made EF track new rows as Modified and throw concurrency exceptions (2026-04-02). This confirms the bullet above.
- No parallel queries on one `DbContext`, not even untracked ones (2025-11-19).

**[AWS-CREDS] Hardcoded AWS credentials, secret-key auth, or region**
Flag in `*.tf`, `appsettings*.json`, `docker-compose.yml`, or adapter code:
- Forcing key/secret authentication instead of letting the **AWS credential chain** discover credentials (in EKS the app is granted an integrated ServiceC role — do not add access-key/secret-key config)
- A **hardcoded AWS region** — and note that Polaris is `eu-north-1`; a hardcoded `us-*`/other region is wrong

**[AUTH-SPOOF] Token authority / spoofable headers not locked down**
Security must-fix:
- JWT/OpenID validation that doesn't pin the **Authority/issuer** so only the intended provider's keys validate ("I hope we're damn sure Authority ensures only Microsoft keys are validated — otherwise anyone can spoof us")
- Trusting forwarded headers (`X-Forwarded-For`, etc.) without the edge (CloudFront) stripping/blocking incoming values — flag if forwarded headers are read for auth/IP decisions without an edge guard

Slack sharpening:
- **Token trust** pins iss, typ, tid and sub, plus exp/nbf with a small clock skew (2026-02). The `preferred_username` claim "is not to authorize" (2025-10-20).
- **A client header can't be a reliable source.** Defaulting it to Web "when we have no clue" makes it unreliable (2025-12-02).
- **Accepting an arbitrary URL on an anonymous endpoint** is "a huge security issue" (phishing / open redirect, 2026-08-04).
- **Refresh tokens** stay in a cookie the web client cannot read. Passing one to a third party "would make the isolation weaker" (2026-08-28).
- **OTPs and secrets use a crypto-secure RNG** (2025-06-18).
- Login and OTP flows need limits on *starting* sessions, not only on failed attempts (2025-07-08).
- A PR touching assume-user needs two reviews (2025-12-04).

**[BUILD-WARNINGS] Compiler warnings left in**
Flag new build warnings (unused usings, obsolete API, nullable warnings). "Fix build warnings — eventually CI will forbid committing with warnings." He treats this as must-fix.

**A local `dotnet build` does not prove this.** CI builds `--configuration Release /warnaserror`,
so a nullable warning is an *error* there and silent in a default Debug build. Verify with the
configuration CI actually uses:

```bash
dotnet build services/<Svc>/<Svc>.sln --configuration Release /warnaserror
```

PROJ-3952 reported "0 errors" from Debug and CI failed on a single CS8604 — surfaced by three
separate jobs, because each one builds the same project transitively. One error can look like
three unrelated failures; read the log before concluding the branch is broadly broken.

**[NO-COMMENTED-CODE] Commented-out code merged in**
Flag blocks of commented-out code in the diff. "Never merge commented code." He will not approve with it present.
He has restated this to the whole team as a standing rule: "never commit commented out code … Just delete the code. Git history … works." (Slack 2026-07-15)

**[PRODUCT-IS-DATA] Code that branches on, stores, or keys by Product**
Products are go-to-market packages of services; **services** (`ServiceContractType`) are the typed
thing code works with, and the product↔service mapping is DB data. The direction is to get
products out of the code entirely. Flag any new `Product`/`ProductType` check, column, enum use or
dictionary key in backend logic, and ask what *service* the behaviour actually depends on.
- #3216 (PROJ-2913): "Products are GTM packages of these services... an attempt to get away products from the code entirely."
- #3207 (PROJ-3359): a product (and country) column on templates "clashes heavily with our product as data not code migration... strip the product for now".
- Standing decision 2026-10-14: "Do NOT check product. Use the services."
- Slack origin of the rule: "Product config scoped to ServiceB should stay in ServiceB" (2025-11-18). "the ProductType enum is getting nuked, and replaced with pure data. If you are building any logic around it, think again" (2026-08-24). Requests take a product *uuid*, not an enum (2026-08-06). Anything branching on contracts or products: "talk to me" first (2026-06-04).

**[CONTRACT-IS-THE-SWITCH] A flag, reconciler or extra guard where the service contract already gates it**
If a capability is entitled by a service contract, the contract *is* the on/off switch — checked at
read time via `ActiveAt(now)`. Do not add a PostHog flag on the backend gate, a reconciler that
provisions/deprovisions rules when contracts change, or a country/retailer guard layered on top.
- #3640 (PROJ-3571): "both workers already gate fk on the contract at read time, so the reconciler isnt needed... support activates the service, the customer ticks the box"; and the country guard was dropped because "company country isnt the employees employment country".
- Standing decisions 2026-10-12 (PROJ-3847): "No PostHog flag on the backend gate. The contract is the switch."
A rollout flag is still expected where production must stay unaffected until a result is trusted (standing decision 2026-09-28) — the rule is: no flag *duplicating* a contract.
The boundary, from Slack 2026-02 → 2026-06: **frontend release flags are the norm**. "Use feature
toggles instead of holding back your code from main", and every new feature ships behind a
frontend PostHog flag that product releases. Backend and frontend ship together. So the question
in review is not "is there a flag?" but "is a *backend* gate duplicating an entitlement the contract
already decides?" A go-live gate can still justify a flag next to the contract ("depends if we want
to keep this away on golive", 2026-10-12).

**[ONE-HOME-FOR-A-RULE] A rule, invariant or pipeline implemented twice — especially a customer-level copy of a company-level path**
The sharpest recurring architecture finding of this period. When a PR adds a customer-level (or
other scope) twin of an existing company-level service/controller/repository, diff the two: the
copies drift within the same PR (different status codes, capped vs rejected, transactional vs
swallowed audit, welcome email sent on one path only). Security-critical invariants (cross-tenant
guards, scope tables) must live in exactly one place. His fix is specific: **not** an
`isCustomerLevel` flag that trades duplication for branching, but extract the flag-free shared
sub-steps and run both routes through one pipeline taking a scope.
- #3176 (PROJ-3274): "Two parallel implementations of one security-critical rule, in two assemblies. Please fold..."; `RoleScopeRules` said one thing while only three of five assignment methods honoured it.
- #3251 (PROJ-3410): customer role subscription service "is basically RoleService... rewritten" and had already drifted in four ways; same PR, a ~86-line verbatim repository query.
Also applies to *derived facts* in CI/infra ("three derivations of the same fact... give phase one source of truth", #3368, PROJ-3464).
Slack instances of the same rule:
- Normalise "in the backend for all reports all the time" (2025-11-10).
- Access is resolved once in the backend and user ids are passed down, so service-e code "knows nothing about access rights" (2026-06-04).
- No per-domain copy of a confidential-read action (2026-03-05).
- "Do we have more than one way to define default activities? … are we hardcoding something somewhere?" (2026-03-27).

**[UNREACHABLE-PERMISSION] A new action no assignable permission can reach for some retailer**
Adding a `CustomerAction`/`CompanyAction` and mapping it into `DefaultPermissionsMappings` is not
enough: for each retailer, check that a permission in `ServicePermissionMap.AlwaysOn[<Retailer>]`
(or a contract entry) that users can actually be assigned maps the action. Blanket grants to
`ManageCustomer`/`CustomerSupport` do not count for RetailerB, whose assignable customer set is
tiny. Otherwise the endpoint 403s for every user of that retailer.
- #3251 (PROJ-3410), marked **Blocker**: `RoleChangeLogRead` reached no TT-assignable permission, so the changelog endpoint 403'd for every TT user in both ServiceC and ServiceD. "better as a decision than something someone finds".
- Slack, earliest form (2025-10-27): "you need to map permissions to any new actions. Otherwise you cant grant them."
- Slack 2026-10-02/06: no department-admin capability "without tag actions", because a service cannot ask ServiceC about rights on a tag. A permission whose scope the authorization system cannot express is unreachable by design. Don't build it yet.

**[EXPAND-CONTRACT] A schema change that old pods cannot run against during rollout**
Old and new pods run side by side during deploy. A column/table rename, a drop, or a changed
meaning on a column the old code still reads will 500 until rollout completes. Renames and drops
need expand/contract: add the new shape, deploy code that reads both/writes new, then drop in a
later release. Also check multi-database migration jobs: one failed schema must not leave the others
ahead with no record.
- Standing decision 2026-10-13: a column rename caused ~25 s of 500s during rollout.
- Slack 2026-04-01: "Dont delete the old data on the first migration."
- #3368 (PROJ-3464): "all six jobs are created before anything is waited on so one failure leaves five schemas ahead".

**[MIGRATOR-PARITY] A schema/enum/field-meaning change the SignedIn→Nova migrators do not follow**
The migration tooling (`tools/Migration`, e.g. `ServiceContractMigrator`,
`HealthCaseTemplateRuleMigrator`, `DefaultRoleMigrator`) writes Nova rows directly. Any change to a
column, an enum, or what a field *means* must be checked against the migrator that writes it, or
migrated data violates the new invariant in prod. Within the migrators themselves, expect: rerun
safety, lookups by the table's natural unique key (adopt the existing row instead of a 23505 that
kills the batch), a content hash that covers every field the write takes, and reuse of the
provisioning code/constants instead of a restated copy.
- Standing decision 2026-10-15: a migrator set `Months = null` and every migrated ServiceB template crashed in prod.
- #3369 (PROJ-3522): tag migrators resolved by minted GUID while the unique key is `(tag_id, value)`; #3452 (PROJ-3610): `DefaultRolePlan` copied `DefaultRoles` instead of reusing it.

**[EVENT-IDEMPOTENCY] Event handler that trusts the event type instead of local replicated state**
Write handlers for **eventual consistency and idempotency**: decide from what is already
replicated in the local DB, not from `EventType` (a `Synced` or redelivered message must land the
same way as `Created`).
- #2909 (PROJ-2798): "Please write event-related handling with the intention of achieving eventual consistency & idempotency... look at what you have already replicated in your local DB rather than the EventType."
- See `/owl-review` [REDELIVERY-SAFETY] and [PUBLISH-AFTER-COMMIT] for the messaging half.

Slack sharpening:
- **Message shape.** Messages are declarative: "A message on the bus should represent the whole database row it is affecting", with a timestamp (`UpdatedAt`) the receiver compares, so "ordering doesnt matter" (2025-08-29). Consumers respect per-submodel `UpdatedAt` (2026-03-04). The stance started on 2025-07-03: "Strong ordering requirements on an async message queue is like begging for" bad data.
- **One event, one change.** An event fires only for the change it describes. `RoleUpdated` on a permission-only update made a consumer wipe subscriptions. A consumer must not treat a partial update as replace-all (2026-06-30).
- **Data migrations bump `UpdatedAt`.** A migration that modifies existing rows "must always update the UpdatedAt timestamp aswell … ALSO applies to ninja edits", or consumers drop the change (2026-03-30).
- **Don't infer the event type from field state.** An updated service-a with an end date is not an "ended" event (2026-05-13).
- **Outbound sends are deduplicated and observable.** Use a table as an atomicity check so a report "can't be sent 5 times" (2026-09-14). An external integration must not be "a blackbox": "Ensure idempotency, deliverability" (2026-08-25).
- **Error queues.** Zero tolerance for a backlog (2026-02-11). Fix the handler rather than moving messages by hand: "plug the hole instead of just continue scooping out the water" (2026-10-06).

**[BUS-IS-NOT-RPC] Request/response emulated over the bus, authorization from bus data, or a write API that returns before it is done**
The bus replicates state. It does not carry requests.
- "Its prone to error to request information required for an operation asynchronously… Just not emulate a request over a event bus... There is REST for that" (Slack 2025-08-18).
- Copying harmless data such as contact info over the bus is fine if it is idempotent and eventually consistent. "The thing we wont do is to use it for any authorization."
- The enrichment pattern is **replicate what you need**: a service replicates the fields it displays, handles the deletion events, and re-checks that the caller may read them ("authorization might differ"). No BFF/facade and no client stitching (2025-12-03, backed by the former tech lead).
- A public write API must not enqueue and return 200: "a 200 OK will not mean processing is finished" (2025-11-24).
Flag: a request-reply pair of messages, a handler that waits for a reply event, an auth decision based on a replicated field, or a 200 from an endpoint whose work happens on a consumer.

**[BAD-INPUT-IS-4XX] Bad input that can reach a 500**
[FAIL-LOUD] means *loud*, not *500*. Invalid input from a user or an integration must be validated
before it hits the DB and returned as a specific 400/422. A 500 from bad input is a backend bug,
in accept as much as in prod.
- "500 -> 400/422 right?" (Slack 2026-07-06); "500 in accept are as serious as in prod … 500 should never be possible to happen" (2026-08-11); "Any 500 should be fixed" (2026-05-25).
- A 500 came from "a DB constraint we are not validating before trying to write to the DB" (2026-02-23). On a check-constraint 500: "our bad … not giving you a 400" (2026-03-23).
- The constraint is still wanted on top: "lets add a database constraint aswell so its totally impossible, if its missed" (2026-03-05).
- Expected auth failure is a 401, and "401 is not a server error" (2026-05-18).
- Import/integration errors must name the problem, not return a generic error (2026-07-17).
- A bug that produced a 500 ships with a small integration test for that case (2026-02-13).
Flag: a DB constraint or unique index with no matching pre-write validation, an enum parse or
`switch` on caller input with no 4xx branch, or a generic error message on an import path.

**[CONTRACT-ENCODES-RULES] A runtime if-statement the API contract could make unrepresentable**
If some values are never valid on create (e.g. `Manager`, `SelfAssigned` role types), use a
separate request enum (`RoleTypeRequest` vs stored `RoleType`) "to encode these ifstatements in the
API contract instead of in the runtime logic … so we dont have to do the same ifstatement in both FE
and BE". Split create and update DTOs when a field (e.g. type) cannot change on update.
(Slack 2026-04-01.) Also: sibling endpoints or functions that serve the same caller keep "exactly the
same interface (input/output)" (2025-05-23). A report whose accepted filters change shape gets
its own report type rather than silently dropping filters.

**[IDENTIFIER-SEMANTICS] An identifier used for a meaning it does not carry**
"Externalidentifier != employmentIdentifier" (Slack 2026-05-15). The employment identifier is metadata
with no uniqueness guarantee. The external identifier means only "an external identifier", and at
least one customer fills it with an identity number, so treat it as sensitive. Flag: using one id
as the other, assuming uniqueness the schema does not enforce, logging the external identifier, or
resolving users across tenants by an id that is unique only within a company. "The natural tenant
divider is customers", and externalId is unique within a company (2026-02-13).

**[LOG-PII-BOUNDARY] Logging or tracking something that is PII on its own, or a session-capable token**
User and account ids may go to Elastic and PostHog ("not PII in itself", "helpful debugging info").
Never log what identifies a person on its own (name, email, identity number), or a token that
could hijack a session. Redacting URLs is fine. (Slack 2026-10-12, which also flagged legacy services
logging tokens.) Flag: a token, an email or an identity number in a log template, a URL logged with
a token in the query string, or an analytics event carrying a name. Also: "dont want noise of errors
that are not errors". Expected conditions are not logged at Error level (2026-03-31).

**[NO-STORED-PROC] Business logic in a stored procedure or DB function the backend does not own in the same change**
"Better to just inject the sql from the backend directly so they are coupled" (Slack 2025-09-24). The
SP and the backend drifted ("90+" vs "91+" bucket) and broke prod. If a DB function is unavoidable,
it changes in the same PR as its caller.

**[CACHE-INVALIDATION] A cache over grants, roles or permissions without invalidation on change**
Granting and revoking must take effect immediately, not after the TTL ("It's easy as a developer to
miss to invalidate a cache in the future", Slack 2026-02-17). Flag: a new cached read of
authorization data with no invalidation on the write path, or a new write path that skips an
existing invalidation.


**Not the tech lead's patterns — see `/zingo-review`**
Findings about per-retailer seed matrices, an unconstrained *grantee*, derived-helper shape gaps,
`Validate`/`Can` duplication and making a request unrepresentable came from reviewer-three's review
lens, not this one. They live in `/zingo-review` so this file keeps simulating one reviewer.

---

#### CLARIFYING QUESTIONS (the tech lead asks before approving)

**[ROUTES] Action-based URL paths**
Look for `[HttpGet("getX")]`, `[HttpPost("createX")]`, `[HttpDelete("deleteX")]`, `[HttpGet("searchX")]` — any route attribute where the path segment is a verb + noun.
Right: `[HttpGet("user/{userId:guid}/documents")]`
Wrong: `[HttpGet("getDocuments")]`
Also flag: camelCase URL path segments (should be kebab-case).
Slack sharpening (2025-08-19, #style-guide-backend): routes are **lowercase, plural resources**, not
the `[Controller]` token: `GET /users/{id}/resource`, not `/User/{id}/resource`. `GET /resources`
lists and `GET /resources/<uuid>` fetches one. Split sub-resources into their own controller (e.g.
`UserResourceController`) instead of growing one big controller. Event logs: "proper REST url!
`GET /service-a/{service-a_id}/events`" (2026-02-18). The same path in every environment, with no
rewrites (2025-10-08). *Tension:* on 2025-11-18 he wrote of a "consensus on using camelCase for
more than one words per segment", and nobody replied. The kebab-case rule above is what the code
review history enforces, so ask rather than block.

**[UPSERT-PREFS] Upsert on user-preference tables**
Look for `AddOrUpdate`, `CreateOrUpdate`, `ExecuteUpdate` (or `SetProperty`) calls in sync workers, import handlers, or event handlers that write to tables containing user-settable preferences (language, notification settings, opt-in flags). The fix is conditional create: check if exists first, only create if absent.
Scope (Slack 2025-09-12): this rule is about *machine* writers overwriting user-set values. A
*user-initiated* `PUT` on a natural key the user owns may upsert ("user preferences makes alot of
sense to do upsert"). Never upsert keyed on a generated id (uuid/sequence), and be wary on very
sensitive updates where a race could overwrite. A sync single-user upsert that "creates if missing
in the given company" produced duplicate users in the wrong company (2026-07-13).

**[EXCEPTION-FLOW] OperationCanceledException caught broadly**
Look for `catch (OperationCanceledException)` at a scope wider than the specific `await` that uses the cancellation token. The catch should be scoped tightly, not at the method or class level.

**[CROSS-SERVICE] ServiceC-owned concerns edited in ServiceB/ServiceA**
Look for modifications to:
- Permission mappings or `TTPermissionsMappings`
- `MaskSsn` / anonymization logic
- Role definitions
- Subscription logic driven by ServiceC contracts
...when the changes are in `services/ServiceB/` or `services/ServiceA/` rather than `services/ServiceC/`.
Slack sharpening:
- A project reference from one service to another service's project is "Illegal!" (2025-12-17).
- No cross-service DB connections (2026-10-12).
- No hard coupling between service-e and data-ops (2026-02-11).
- A new feature goes to the service that owns its domain, not into ServiceC ("our wannabe monolith", 2026-02-11).
- Don't couple a domain lookup tightly to ServiceC's authorization endpoints (2025-11-19).

**[REPO-PATTERN] Repository method that does no I/O**
Look for repository methods that receive an already-loaded entity and only read/project its properties without any database call (`Task.FromResult(...)` wrapping entity field access). These belong in the controller or a mapper, not the repository layer.
Team agreement (Slack 2025-10-08, he asked and four peers agreed): a **controller may call a
repository directly** "when it makes sense", e.g. to find a resource's owner before the auth check.
A service exists only when it adds something (several repo calls, a transformation): "no law that
you have to add a abstraction layer that makes no point". Repositories return primitives or domain
objects. "call the repo and check if you get a null or the domain". Don't put HttpContext or token
claims in a service. So do **not** flag controller→repository by itself, but do flag a pass-through
service. For new backend code: "backend, follow what we have" (2026-10-06).

**[VALIDATION-SEMANTICS] Missing server-side validation for conditional requirements**
Look for DTOs where some fields are only required when another field has a specific value (e.g., dates required when a toggle is true, value required when a type is string-valued), but no `[Required]` or guard logic enforces this in the controller or a validator.
Also ask (Slack):
- Is input validated before it reaches the DB (see [BAD-INPUT-IS-4XX])?
- Is a date a date, not a full timestamp (2025-08-15)?
- Do limits consider dates, so a future end date cannot bypass them (2026-03-02)?
- Do search endpoints filter ended employees (2026-02-05)?
- For partial updates: a null sub-object means "don't touch", while nulls inside a provided object mean null (2026-03-30).

**[FEATURE-SCOPE] Backend endpoint wider than feature scope**
If the PR description says the feature is scoped to a specific retailer/tenant (e.g., MH-only) but the backend endpoint has no tenant guard, ask: what prevents other retailers from calling this endpoint? Is the frontend-only gate intentional and sufficient?
Slack: a restriction belongs in the permission/feature system, "not just greyed out in the frontend" (2025-12-12).

**[CAPABILITY-IS-NOT-ELIGIBILITY] "Who can do X" used as "who should be listed for X"**
Being able to perform an action is not the same as being eligible to be picked for a role. Asking
ServiceC who can manage a case returns every support user and global admin. Authorization has two parts:
what the caller may see or set, and who can actually hold the role. The domain service may own the
second (Slack 2025-11-10). Also, an empty set of authorized users does not mean the caller lacks
permission: return 200 with `[]`, not 403 ("A wrong assumption in the backend that no authorized
users means no permission", 2026-01-29).

**[MISSING-TEST] No integration test for new persistence round-trip**
Look for new `POST`/`PUT`/`DELETE` controller endpoints with no corresponding `IntegrationTests` project test that exercises the full round-trip: HTTP call → database write → verification. Unit tests that mock the repository do not count.

Important nuance he repeats: integration tests should test **round-trips and access/permission scenarios**, NOT unit-level logic paths. He explicitly notes that "Claude tends to ALWAYS" write integration tests that are really unit tests, and he asks for them to be removed. So when an agent adds integration tests, check they exercise the HTTP→DB→verify path or permission/access matrix — not branch coverage of a single method. Schema changes with no test touched also draw a "why no test?" question.

Slack nuance (2025-11-24): "Please write tests for new endpoints" (integration), and "still write unit
tests for testing branching logic of each layer (service, controller)". The tests he removes are
integration tests doing unit work and unit tests that assert nothing, not unit tests of
branching. FluentAssertions is not used: "snuck into service-e… can you remove it?" (2026-01-20). Test
timeouts should be about 1 s, not 10 s (2026-02-11).

He is also strict that tests must **assert real logic, not just pass**: flag mocks/assertions like `It.IsAny<Guid>()`, asserting only that a call happened, or loose matchers that would pass regardless of correctness. "Don't just `IsAny<Guid>`. Please validate your logic in the tests, don't just make the tests pass!" A new endpoint with *no* tests at all is a hard must-fix for him ("makes no sense to not have any tests... please make it a habit").

**[INTEGRATION-TEST-SPARSITY] Too many integration tests where unit tests suffice**
The flip side of MISSING-TEST: the tech lead treats integration tests as **expensive (time/CI budget)** and wants them **sparse** — usually a single happy-path is enough. When a PR adds several integration tests covering scenario/branch variations (e.g. granted→true, not-granted→false, leak-guard→false all as integration tests), flag it: keep at most ONE happy-path integration test and **move the rest to unit tests** (mapping tests, scope-resolution tests, helper-level assertions). His verbatim: "Drop these tests please, i dont think it adds a lot of value, and a integration test its quite expensive (time budget-wise)... What you can do is move it to a unit test though. Future consideration is to always be sparse with integrationtests, mostly a single one testing a 'happy' path is enough." So default new-behavior coverage to unit tests, reserving integration for one round-trip/access-matrix happy path. (Source: PROJ-3183 review.) Repeated since: #3253 (PROJ-3376) "Please do not write a billion integration tests... 1-3 for the happy path, sometimes selective unhappy paths"; #3134 (PROJ-3297) no integration tests for a DB check constraint — "we dont need to write tests to check 'does postgres actually do its job'". The exception he keeps: one real-Postgres test where the thing at risk is SQL/LINQ translation (#3420, PROJ-3657).

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

Slack sharpening:
- **Quotes.** "Silent errors are worse than 500" (2025-09-19). "Failing badly is better than failing silently" (2025-08-27). "Throwing is good when your assumptions break", and "nested if statements like this is a big red flag" (2026-05-13).
- **All-or-nothing.** Validate the whole batch before writing, then throw so the message dead-letters. Partial success on an integration manifest: "No… Too many edge cases with catastrophic consequences" (2026-02-25).
- **Enum filters fail closed.** A filter like `Source == External` let a new enum value through and echoed ~6k rows to a partner. Ask for "explosive protection" when a new enum value would change who matches (2026-04-15).
- **"We don't know" is not a root cause.** "That probably means that we are shadowing an issue." Revert if needed, keep the tests, reproduce, fix (2026-04-02). Don't mute alerts: "Silencing a problem is not a good solution" (2025-10-27).
- **Loud is not 500 for bad input.** See [BAD-INPUT-IS-4XX].
- **Scoped exceptions where he chose a safe default:**
  - an unsupported *customer-supplied* setting (a template font) falls back to one we have (2026-09-28);
  - a rollout gate whose config fetch fails falls back to the legacy path (2026-09-29).
  Don't flag those two shapes. Ask that the fallback be logged.

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
Shape (Slack 2025-08-05): one shared `PaginationResponse`. Controllers take an **item** index ("item,
not page index") plus a limit, and the limit is capped. Plan list sizes for "1000 [customers] at
least" (2025-11-10). A heavy export should be "batched instead of a mega query" or run off-hours
(2026-06-23). For [BATCH-DB]: many `SynchronizeChildList` calls in one update is "a latency bomb"
(2026-03-06).

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

(PROJ-3618: three separate instances in one PR. A dashboard column unioning `inserted_at` with
`planned_at` meant one parse broke whichever half it did not suit; a pause window rewritten to
bracket local days was inert because the repository compares against `UtcNow.Date`, and skipped a
day at negative offsets; and a timezone guard asserted a wire shape the DTO never sends. All three
were invisible to tsc, eslint, 2000 unit tests, real-browser verification in two zones, and a
diff-scoped pre-emptive review — because every one of them lived in code adjacent to the diff
rather than in it.)

**[DATA-FIX-ROUTE] Data changed through the wrong channel**
Ask how data gets in or gets corrected. His order of preference: an existing (or a management)
**API** first; a **migration** for corrective fixes when no API fits ("fine, but also overkill if
you can do it over APIs"); never direct DB write access for ops. Defaults that only developers
change belong **in code**, not DB rows — unless non-developers are explicitly meant to edit them.
- #3828 (PROJ-4054): "No ops should be done through write access, either APIs and for corrective fixes, migrations."
- #2909 (PROJ-2798): seeding a retailer activity via migration — "we should either create a mgmt API and just insert it there"; #3207 (PROJ-3359): "defaults in code is easier to manage than DB data, UNLESS we explicitly want non-developers to change the defaults".
- Slack: a migration on the *producing* service emits no events. Roles seeded by an ServiceC migration never reached ServiceD, "a ticking timebomb in prod" (2026-06-17). When the data is replicated, go through the API so the events fire, or bump `UpdatedAt` and re-publish (see [EVENT-IDEMPOTENCY]).
- Slack: prod reads also go through APIs. Wanting to check data is not "a good enough reason" for DB access (2026-09-14). "Getting access is a PR" (2026-10-14). Seeding in the deploy step "would wipe data randomly" (2025-11-14).
- Slack: fix the producer first, then clean the existing data (2025-06-25).

**[PRODUCER-OWNS-DERIVATION] A consumer re-deriving something the producing service already knew**
When service B reconstructs a value from parts (a URL, a status, a scope) that service A had in
finished form, ask whether A should send the finished value so B only renders/stores it. Copies of
a validation rule on both sides drift silently when one is loosened.
- #3280 (PROJ-3377): "could ServiceC just always send a finished absolute url here, so ActionValue has one shape and service-d only renders it?... service-d is re-deriving something ServiceC already knew."
- Slack applies the same rule backend→frontend. Totals computed from percentages in the frontend were "totally wrong… the denominator differs", so the aggregate moved to the backend (2026-01-27). The frontend resolving names by listing 1000 users: "Next time ask BE to do its job" (2026-03-11). Data functions return name together with id (2025-05).

**[PAGE-AUTHZ-CONTEXT] A screen that calls an extra endpoint just to learn a fact**
Each endpoint a page calls adds its permission to what the page needs. A page that fetches another
resource (products, contracts) only to read one flag breaks for users who hold the page's
permission but not that one. Ask for the fact on an endpoint the page already uses, or a
per-company feature read.
- #3640 (PROJ-3571): "the deviant tab shouldnt need ProductContractsRead just to know if fk is on, it breaks the auth context of the page." (Accepted for now: "Im willing to bet we will regret it later.")

**[PR-SCOPE] Scope beyond the ticket, or unrelated changes riding along**
Endpoints outside the ticket's technical scope go in a stacked follow-up PR; unrelated file edits
pollute `git blame`; the PR title becomes the permanent commit message, so it must say everything
the PR changes. A decided refactor and an undecided design change go in separate PRs.
- #3806 (PROJ-3925): "This is a monster of a PR. Not just in lines and files changed, but in scope. In the future try to split things."
- #3251 (PROJ-3410): three role-assignment endpoints "arent in 3410s technical scope... could they go in a stacked follow-up pr?"
- Slack: "Dont need this monster to grow. Already at 2k line changes" (2025-05-19). About 330 lines per PR "is way more optimal and manageable than 2500" (2026-01-30). "Lets not start implementing anything just because [an AI reviewer] suggested it" (2026-01-20). Split an unrelated infra fix into its own PR merged first (2026-07-21). He asks for the ticket when PR scope and ticket don't match (2026-04-01). The boundary with [DEFER-OWN-MESS]: a *small* fix to code the PR already touches goes in now. A follow-up ticket "will never be prioritized until it's actually a problem" (2026-02-17).

**[COMMENT-NOISE] AI-generated comment volume, prompt context in comments, or always-loaded context files**
He measures it: comments that narrate the line below, restate reasoning, or leak the prompt
("as the ticket asks...") get cut; rationale belongs in the PR description. Also flag additions to
`AGENTS.md`/`CLAUDE.md` that are specific to one feature — those load into every context.
- #3420 (PROJ-3657): "197 of ~790 added prod lines are comments. bar should be higher"; #3598 (PROJ-3790): "28% comment lines vs 4-6% across the rest of the services".
- #3340 (PROJ-3193): "I would suggest to not commit this in the shared agent file so its loaded into every single context."
- Slack: "code comments goes stale really really quick", "never restate logic", "apply to all PRs" (2026-09-07/24). The same bar applies to PR descriptions and Slack: LLM text "max a few lines… If everything is important, nothing is" (2026-02-17). Don't paste raw LLM output; keep it to 3-5 sentences (2026-03-09).

---

### Step 4 — Format findings

Output in the tech lead's style: code-specific, no preamble, grouped by severity.

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

### Standing decisions (dated, from Slack/Jira — check the ticket against these first)

Newer decisions override older patterns in this file. Each is the tech lead's unless noted.

**From the full Slack walk (2025-05 → 2026-10), oldest first. Where two entries disagree, the later one wins.**

- 2025-05-19 #project-new-service-e: model a state by whether the row exists, not by an extra bool. An `available` flag next to `selectable` gave "5 states with 2 undefined". → [EF-MODELING]
- 2025-05-23 #project-new-service-e: sibling functions (per department, per cost centre) get "exactly the same interface (input/output)", so a caller can "just swap the name".
- 2025-06-18 #ai: OTP and other secrets come from a crypto-secure RNG. An exclusive upper bound that never yields 9 made the OTP "46% less random".
- 2025-07-08 #frontend: setting HTML directly is "a XSS entrypoint", "we need to get rid of it". → [HTML-ENCODING]
- 2025-08-05 #standup: one shared `PaginationResponse`. Controllers take an item index ("item, not page index") and a capped limit. → [PAGINATION]
- 2025-08-18 #project-nova: "Just not emulate a request over a event bus... There is REST for that." Copying harmless data over the bus is fine if idempotent; "The thing we wont do is to use it for any authorization". → [BUS-IS-NOT-RPC]
- 2025-08-19 #project-nova: "All tables no matter what they are, should have an inserted_at" (relation tables too). `modified_at` may be skipped only on immutable data. Keep the `inserted_at`/`modified_at` naming. → [EF-MODELING]
- 2025-08-19 #style-guide-backend: routes are lowercase plural resources (`/users/{id}/resource`), not the `[Controller]` token. Split sub-resources into their own controller instead of growing `UserController`. → [ROUTES]
- 2025-08-27 #backend-pull-requests: validate everything before a copy loop, then throw so the message lands on the error queue. "Failing badly is better than failing silently." → [FAIL-LOUD]
- 2025-08-29 #project-nova: messages are declarative, not imperative. "A message on the bus should represent the whole database row it is affecting", with a timestamp the receiver compares against. → [EVENT-IDEMPOTENCY]
- 2025-09-12 #style-guide-backend: PUT-as-upsert is fine on a natural key the user owns ("user preferences makes alot of sense to do upsert"). Never upsert on generated ids or for very sensitive updates. → [UPSERT-PREFS]
- 2025-09-15 #project-nova: don't copy an owner id (`CompanyId`) onto a child entity when the parent's replica already has it: "join in the company id from the user". The field was removed. → [EF-MODELING]
- 2025-09-19 #backend: a role check is not tenant authorization. An endpoint that checks role "not if you are actually authorized on a specific company" is cross-tenant exposure. → [MULTI-TENANCY]
- 2025-09-19 #project-new-service-e: "Silent errors are worse than 500." → [FAIL-LOUD]
- 2025-09-24 #backend-pull-requests: no stored procedures. "Better to just inject the sql from the backend directly so they are coupled". An SP/backend bucket mismatch broke prod. → [NO-STORED-PROC]
- 2025-10-08 #project-nova (team agreement): a controller may call a repository directly "when it makes sense". Add a service only when it adds something: "no law that you have to add a abstraction layer that makes no point". "Never return a domain object from a controller." → [REPO-PATTERN]
- 2025-10-21 #project-nova: enums in the DB are stored as strings, "uniform with shared config". Today it is per property (`HasConversion<string>()`), not one shared convention. → [ENUM-OVER-STRING]
- 2025-10-27 #project-nova: "you need to map permissions to any new actions. Otherwise you cant grant them." → [UNREACHABLE-PERMISSION]
- 2025-10-27 #project-nova: on an upload endpoint, "can I (if i know the ID) upload documents into any health case?" Resolve the owner and authorize before writing, not only on reads. → [AUTH-ORDER]
- 2025-10-30 #project-nova: a permission follows where the thing is attached ("A company? Use a company action? A customer? customer action? A retailer? retailer action?"). Don't reuse CompanyAdministrator for a domain admin; define a dedicated permission. → [PERMISSION-PLACEMENT]
- 2025-11-03 #project-nova: reading or editing a health case is a `UserAction` ("the action is on the user"), even when granted over a whole company. → [PRIVILEGE-SCOPE]
- 2025-11-05 #project-nova: use the C# `required` keyword on DTOs, not `[Required]` ("compile time guarantees... the keyword is enough"). → [DTO-NAMING]
- 2025-11-10 #project-nova: being able to do an action is not being eligible to be listed for it (e.g. case-manager candidates). → [CAPABILITY-IS-NOT-ELIGIBILITY]
- 2025-11-10 #project-new-service-e: normalisation happens "in the backend for all reports all the time", not per report in the frontend. → [ONE-HOME-FOR-A-RULE]
- 2025-11-10 #polaris: no dev authorization-bypass user in accept, because accept holds customer data.
- 2025-11-13/20 #project-proj-service-b: annotate `[ProducesResponseType]` so Swagger documents the success shape. → [DTO-NAMING]
- 2025-11-14 #backend: URL-encode special characters in a department-tag value instead of counting on a separator that never appears in a name. → [IDENTIFIER-SEMANTICS]
- 2025-11-18 #project-nova: "Product config scoped to ServiceB should stay in ServiceB". ServiceC's product is "just an enum". → [PRODUCT-IS-DATA]
- 2025-11-19 #project-nova: no parallel queries on one `DbContext`, not even untracked ones. Run them sequentially.
- 2025-11-24 #project-nova: a new appsetting goes in three places (`appsettings.json`, `docker-compose.yml`, `infra/k8s`). → [DEPLOY-PIPELINE]
- 2025-11-24 #project_oneentry: a public write API must not enqueue and return 200: "a 200 OK will not mean processing is finished". → [BUS-IS-NOT-RPC]
- 2025-11-24 #project-nova: "Please write tests for new endpoints" (integration), and "still write unit tests for testing branching logic of each layer". → [MISSING-TEST]
- 2025-11-26 #project-nova: "No int ids. Any mapping between old ids will only be during a migration. And not in the DBs here." → [EF-MODELING]
- 2025-12-01 #project-proj-service-b: a replicated `company_id` is a non-null FK. Out-of-order events are handled by replaying the message, not by a nullable column. → [EF-MODELING]
- 2025-12-03 #project-proj-service-b (with the former tech lead): no BFF or client stitching. A service replicates the fields it needs, handles deletion events, and re-checks that the caller may read the replicated data. → [BUS-IS-NOT-RPC]
- 2025-12-12 DM: restricting a configuration belongs in the permission/feature system, "not just greyed out in the frontend". → [FEATURE-SCOPE]
- 2025-12-17 #project-nova: a project reference from one service to another service's project is "Illegal!" → [CROSS-SERVICE]
- 2026-01-19 DM: code gates on the Action. Which permission grants it is decided in the ActionMap, not in the code. → [PERMISSION-PLACEMENT]
- 2026-01-20 #backend: "Lets not start implementing anything just because [an AI reviewer] suggested it." → [PR-SCOPE]
- 2026-01-20 #project-nova: FluentAssertions is not used in tests. "can you remove it?" → [MISSING-TEST]
- 2026-01-27 #project-new-service-e: totals were computed from percentages in the frontend ("the denominator differs"). The aggregate belongs in the backend. → [PRODUCER-OWNS-DERIVATION]
- 2026-01-29 #project-nova: "no authorized users" does not mean "no permission". Return 200 with `[]`, not 403. → [FAIL-LOUD]
- 2026-01-29 / 02-02 #repo-retailer-b: user-facing endpoints carry "business rules… that make sense from a logged in user's perspective but not service2service". Only the `*.Sync` endpoints accept service tokens. → [S2S-VS-USER-API]
- 2026-02-05 #project-proj-subscription-and-roles: "ended employees should be filtered for most search endpoints."
- 2026-02-11 #project-nova: zero tolerance for an error-queue backlog. Every failing message gets a bug ticket.
- 2026-02-11 #project-nova: service-e is not hard-coupled to data-ops. A new feature goes to its owning service, not into ServiceC ("our wannabe monolith"). → [CROSS-SERVICE]
- 2026-02-17 #project-nova: role/permission caches must invalidate on grant and revoke, so changes take effect at once and not ~5 min later. → [CACHE-INVALIDATION]
- 2026-02-17 DM: do a small fix in your own PR now. A follow-up ticket "will never be prioritized until it's actually a problem". LLM text in PRs: "max a few lines… If everything is important, nothing is." → [DEFER-OWN-MESS] [COMMENT-NOISE]
- 2026-02-23 #project-nova: "We push to accept and prod on every merge to main… Use feature toggles instead of holding back your code from main." Don't deploy branches to accept. "Before writing code, just align the approach!"
- 2026-02-25 #repo-retailer-b: an integration manifest is all-or-nothing. Partial success: "No… Too many edge cases with catastrophic consequences." → [FAIL-LOUD]
- 2026-03-02 #project-nova: "dont touch service-a sync with that sort of logic". The backend has no "historical" service-a, only an end date, and the 2-ongoing limit is judged by dates. → [S2S-VS-USER-API]
- 2026-03-05 #project-nova: **reversal**. A UserPermission may now grant CompanyActions on the targeted user's own company ("That simplification just didnt work out"). → [PRIVILEGE-SCOPE]
- 2026-03-05 #project-nova: add a DB constraint as well as backend validation "so its totally impossible, if its missed". Hitting it must still be a 400 ("our bad … not giving you a 400"). → [BAD-INPUT-IS-4XX]
- 2026-03-05 #project-proj-service-b: no domain-specific confidential actions. Identity-number reads go through `UserReadConfidential`. → [ONE-HOME-FOR-A-RULE]
- 2026-03-06 #project-proj-service-b: many `SynchronizeChildList` calls in one "update case" function is "a latency bomb … we cant go live with this code". → [BATCH-DB]
- 2026-03-09 #project-proj-service-b: store `ResponsibleUserId` and look the name up in the local user replica. Don't store the name ("Its not a trip to ServiceC"). → [EF-MODELING]
- 2026-03-11 DM: the frontend resolving names by listing 1000 users is "super ineffektivt". "Next time ask BE to do its job." → [PRODUCER-OWNS-DERIVATION]
- 2026-03-18 #standup: a feature flag reads the dedicated action it is about (e.g. `CreateSupportCase`). It must not be derived from other actions. → [AUTHORIZED-FEATURES-MISUSE]
- 2026-03-23 #project-nova: "If you remove an enum value that is in a DB, please add a tiny migration that removes it from all DBs." → [EF-MODELING]
- 2026-03-25 #project-nova: "Be abit mindful about creating/modifying permissions for TT. Actions are fine." "If its for the retailer its a retailer action." → [PERMISSION-PLACEMENT]
- 2026-03-30 #project-nova: a migration that modifies existing data must "always update the UpdatedAt timestamp aswell … ALSO applies to ninja edits". → [EVENT-IDEMPOTENCY]
- 2026-04-01 #project-nova: separate request and stored enums (`RoleTypeRequest` vs `RoleType`) "to encode these ifstatements in the API contract instead of in the runtime logic". Split create and update DTOs. → [CONTRACT-ENCODES-RULES]
- 2026-04-01 #project-proj-service-b: "Dont delete the old data on the first migration." → [EXPAND-CONTRACT]
- 2026-04-01 #alerts-polaris-accept: `UpdatedAt` is the concurrency token. "We should not have two concurrency tokens regardless." → [EF-MODELING]
- 2026-04-02 #alerts-polaris-accept: "Im not satisfied with the answer: 'we dont know'. That probably means that we are shadowing an issue." Revert, keep the tests, reproduce, then fix. → [FAIL-LOUD]
- 2026-04-15 #project-nova: `Source == External` let a new enum value echo ~6k service-as back to a partner. Filters on an enum need "explosive protection for what counts as external". → [FAIL-LOUD]
- 2026-04-24 #project-nova: don't reuse the admin products endpoint to toggle a frontend feature, because it "might require different permissions". → [PAGE-AUTHZ-CONTEXT]
- 2026-05-13 #project-nova: "nested if statements like this is a big red flag". "Throwing is good when your assumptions break." → [FAIL-LOUD]
- 2026-05-15 #project-nova: "Externalidentifier != employmentIdentifier." → [IDENTIFIER-SEMANTICS]
- 2026-05-19 #repo-retailer-b: an external migration calls our frontend APIs. "its mostly our responsibility to ensure we do not break our external dependencies… Or atleast inform about it". → [S2S-VS-USER-API]
- 2026-05-25 #infrastructure: "Any 500 should be fixed." Alert on a single 5xx, and alerts are IaC. → [BAD-INPUT-IS-4XX]
- 2026-05-25 #project-nova: "think critical about AuthorizedFeatures". One flag gated two features, and "you might have access to one but not the other. We need to model that". → [AUTHORIZED-FEATURES-MISUSE]
- 2026-05-29 / 06-09 #frontend #quality-assurance: every new feature goes behind a frontend PostHog flag. Backend and frontend ship together, and feedback comes from code review into main behind the flag, not from a branch on accept. This is the release flag. The backend entitlement is still [CONTRACT-IS-THE-SWITCH].
- 2026-06-04 #project-proj-service-e: resolve access in one place in the backend and pass user ids down, so service-e code "knows nothing about access rights". ServiceE access runs on tags. → [ONE-HOME-FOR-A-RULE]
- 2026-06-17 #alerts-polaris-accept: roles seeded by a migration in ServiceC never reached ServiceD, a "ticking timebomb in prod". A producer-side migration emits no events. → [DATA-FIX-ROUTE]
- 2026-06-26 #infrastructure: "dont leave undestroyable terraform resources on a branch since they block terraform apply on main". Split terraform into secrets first, then workload. → [DEPLOY-PIPELINE]
- 2026-06-30 #project-nova: an event fires only for the change it describes, and a consumer must not treat a partial update as replace-all. "always question hard when things doenst make sense". → [EVENT-IDEMPOTENCY]
- 2026-07-06 / 08-11 #alerts-polaris(-accept): bad integration input surfacing as a 500 is a bug ("500 -> 400/422 right?"). "500 should never be possible to happen." Accept 500s are "as serious as in prod". → [BAD-INPUT-IS-4XX]
- 2026-07-15 #project-nova: "never commit commented out code … Just delete the code. Git history … works." He calls this a standing team rule. → [NO-COMMENTED-CODE]
- 2026-08-04 #seru-repo-integration: accepting an arbitrary URL on an anonymous endpoint is "a huge security issue" (phishing). → [AUTH-SPOOF]
- 2026-08-17 #seru-repo-integration: `/authorizedFeatures` is deprecated for `/features`, which exposes the authorized actions "so the client can do its own decision". → [AUTHORIZED-FEATURES-MISUSE]
- 2026-08-17 #project-proj-signedin-migration: Nova sends from the legacy sender on repo.se, because customers whitelist it. Migrated customers get notification suppression. → [MIGRATOR-PARITY]
- 2026-08-24 #project-nova: "the ProductType enum is getting nuked, and replaced with pure data. If you are building any logic around it, think again." → [PRODUCT-IS-DATA]
- 2026-08-25 #project-nova: an outbound integration must not be "a blackbox". Capture and visualise sends, and "Ensure idempotency, deliverability". → [EVENT-IDEMPOTENCY]
- 2026-08-28 #seru-repo-integration: the refresh token stays in a cookie the web client cannot read. Handing it to a third party "would make the isolation weaker". → [AUTH-SPOOF]
- 2026-09-07 #ai, repeated 09-24 DM: "code comments goes stale really really quick", "never restate logic", "apply to all PRs". → [COMMENT-NOISE]
- 2026-09-07 DM: no new Nova↔SignedIn link table "here and now". Use ServiceC's existing migrations table later. → [REUSE-FIRST]
- 2026-09-14 #security: wanting to check data is not "a good enough reason" for prod DB access. Script it over the APIs. On 10-14: "Getting access is a PR". → [DATA-FIX-ROUTE]
- 2026-09-14 #project-nova: use the reports table as an atomicity check, so an outbound report cannot be sent five times. → [EVENT-IDEMPOTENCY]
- 2026-09-14 #project-proj-signedin-migration (tentative): global templates are a one-time setup, identifiable, with no duplicates. → [MIGRATOR-PARITY]
- 2026-09-21 DM: automation with "enormous complexity with large interventions in existing architecture" for "very little effort saved" is rejected. "Larger things need to go through a planning process." → [NECESSITY]
- 2026-09-22/23 DM: he disliked a design "because it poked into the role system — we can do things around it instead". Customer support is a role and global admin "is an override". → [NECESSITY]
- 2026-09-28 #alerts-polaris: when customer-supplied config (a template font) is unsupported, "default to a font we do have". Installing fonts is "a very shortsighted solution". This is a scoped exception to [FAIL-LOUD].
- 2026-09-28 / 10-14 #ask-data: service-e "is not migrated... its computed". Verify the source rows and "actually do the math" instead of comparing totals across environments.
- 2026-09-29 DM: percentage rollout is decided by a sticky client value before the first paint. A failed config fetch falls back to the legacy path as the "safe default", and the default flips only at 100%.
- 2026-09-29 #project-proj-signedin-migration: migrate VAB templates even where the service is off, but closed for reporting. → [MIGRATOR-PARITY]
- 2026-09-30 #project-proj-signedin-migration: the deviant engine is paused per customer during migration (`CustomerDeviantPause`). → [MIGRATOR-PARITY]
- 2026-10-02/06 DM: no department admin yet "without tag actions", because a service cannot ask ServiceC about rights on a tag. → [UNREACHABLE-PERMISSION]
- 2026-10-06 #alerts-polaris: clearing a dead-letter queue by hand is wrong: "plug the hole instead of just continue scooping out the water". → [EVENT-IDEMPOTENCY]
- 2026-10-06 DM: "backend, follow what we have." → [REUSE-FIRST]
- 2026-10-07 #project-proj-signedin-migration: manager and employee roles belong on the company, admin roles on the customer. → [PERMISSION-PLACEMENT]
- 2026-10-08 #project-proj-signedin-migration (#3906): CoA, CA and DA become one customer-level Administration role. A recursive top-department grant is skipped, because it would escalate to company. → [PRIVILEGE-SCOPE]
- 2026-10-08 #project-proj-signedin-migration: role names are translation keys; Swedish for the pilot, local + English for new roles. → [REUSE-FIRST]
- 2026-10-09 #project-proj-signedin-migration: the migrated service-a log shows the real actor, not "system" (PROJ-4328). → [MIGRATOR-PARITY]
- 2026-10-12 #alerts-signedin-login: user and account ids may be logged ("not PII in itself"). Never log PII on its own (name, email, identity number) or a session-capable token. → [LOG-PII-BOUNDARY]
- 2026-10-12 #backend: Slack discussion stays in English ("Stick to :gb: in slack"). → [COMMENT-NOISE]
- 2026-10-14 DM: "Map it but featureflag it on the service." → [PRODUCT-IS-DATA]
- 2026-10-15 #project-proj-signedin-migration: replace go-live booleans with a go-live date that the dependent flags respect.
- 2026-10-15 PR #3985 (PROJ-4404, closed): changing how the migration derives employment start, so a re-run rewrites live users' data, is "a big decision to take on a whim". A migration behaviour change for live customers needs agreement first. → [NECESSITY]

**Earlier entries (first mining pass):**

- **2026-09-28 (Slack):** production stays unaffected until the result is trusted; then ship behind a feature flag so it can be rolled back.
- **2026-10-06/08 (PROJ-3847):** "No ServiceC changes" for subscriptions. Adding a `ServiceContractType` is not an ServiceC change. Contracts need not exist before merge — the migration script inserts them.
- **2026-10-12 (Slack):** "if we have the contract, we might not need a posthog flag." Same day, tech lead in PROJ-3847: "No PostHog flag on the backend gate. The contract is the switch." → [CONTRACT-IS-THE-SWITCH]
- **2026-10-12 (Slack):** reuse existing flags and mechanisms ("we don't invent a new way"). No cross-service DB connections. → [REUSE-FIRST]
- **2026-10-13 (Slack):** a column rename caused ~25 s of 500s during rollout (old pods on the new schema). Renames need expand/contract. → [EXPAND-CONTRACT]
- **2026-10-14 (Slack):** "Do NOT check product. Use the services. Product<->service mapping is a DB thing." → [PRODUCT-IS-DATA]
- **2026-10-15 (Slack):** when changing the DB schema or what a field/enum means, check that the SignedIn→Nova migrators (e.g. `ServiceContractMigrator`, `HealthCaseTemplateRuleMigrator`) keep up. A migrator set `Months = null` and every migrated ServiceB template crashed in prod. → [MIGRATOR-PARITY]
- **2026-10-15 (Slack):** data fixes: "a migration is fine, but also overkill if you can do it over APIs." → [DATA-FIX-ROUTE]
- **2026-10-16 (Slack, PROJ-4061):** "Always be careful about building a mechanism we dont have." "We have one live prod customer, manual turning stuff on is reasonable." "If required to avoid data loss, use a migration before building something new." "Something new needs taste, judgment and consensus. Something existing is just to go hard." → [NECESSITY], [DATA-FIX-ROUTE]

### Step 1 — Fetch the ticket

```bash
acli jira workitem get <TICKET_ID>
```

### Step 2 — Ask the architecture questions the tech lead would ask

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
- Does the ticket prescribe a *mechanism* (a specific field, endpoint shape, or data location) — especially one relayed from product/customer? Treat it as a suggestion, not a spec: model it the way the system actually works and push back if they diverge. (PROJ-3183: the ticket asked for a `hasSuuntaReporting` boolean on `authorizedFeatures` and "per-user"; the correct model was a company-level `CompanyAction` read via the authorization endpoint — three rework cycles for not settling this first.)
- New permission? Decide UP FRONT: User vs Company scope; contract-gated vs always-on; and which existing feature it mirrors.
- Is anything being added to `authorizedFeatures` for a non-FE consumer? It almost certainly belongs on the authorization endpoints instead.

**Altitude — where does the decision live?**
- Does the design branch on Product (or store it)? Which *service* does the behaviour really depend on?
- Is the capability entitled by a service contract? If so, is the contract checked at read time as the only switch — no backend PostHog flag, no reconciler, no extra country/retailer guard?
- Does production need protecting until the result is trusted? If yes, which *existing* flag mechanism carries the rollback?
- Is there a customer-level twin of a company-level path planned? How will both share one pipeline (scope parameter), so the rule lives in one place?
- For every new action: which assignable permission reaches it for **each** retailer (check `ServicePermissionMap.AlwaysOn[RetailerB]`)?
- Does the page that uses this need any new permission just to read one fact?
- Does a consumer service re-derive something the producer could send finished?

**Rollout and data:**
- Does any schema change rename/drop/redefine something the running pods read? What is the expand/contract sequence?
- Which SignedIn→Nova migrator writes the touched table/field, and does it still produce valid rows after this change?
- How does the data get in or get fixed — API, migration, or (never) direct write access? Are defaults code or data, and who edits them?
- Do event handlers decide from replicated local state (idempotent on `Synced`/redelivery), not from `EventType`?
- Is the scope one PR? Anything outside the ticket's technical scope goes in a stacked follow-up.

**Slack-pass questions:**
- Does any cross-service step *request* something over the bus, or authorize from replicated data? Which fields get replicated, and are deletions handled? ([BUS-IS-NOT-RPC])
- Which inputs can reach a DB constraint or enum parse, and is each a specific 4xx? ([BAD-INPUT-IS-4XX])
- Are invalid-on-create values unrepresentable in the request contract? ([CONTRACT-ENCODES-RULES])
- Does the design use an identifier (external, employment, legacy int) for a meaning or uniqueness it does not carry? ([IDENTIFIER-SEMANTICS])
- Does a "who can do X" lookup double as "who is eligible for X"? ([CAPABILITY-IS-NOT-ELIGIBILITY])
- Is any authorization data cached, and where is it invalidated? ([CACHE-INVALIDATION])
- Does a data migration bump `UpdatedAt`, and do consumers see the change? ([EVENT-IDEMPOTENCY], [DATA-FIX-ROUTE])
- Is a larger design change going through planning instead of straight to implementation? "Before writing code, just align the approach!" ([NECESSITY])

Output as: *"Before implementation, answer these questions:"* — listed per area. Not as findings, but as design decisions to resolve.

---

## Tips

- Run against a PR before pushing for review: `/ghost-review` (auto-detects current branch)
- Run against a ticket during architecture phase: `/ghost-review PROJ-2547`
- The "Already handled" section is important — it tells you what you can answer immediately if he asks
- Auth-order, multi-tenancy, privilege-scope, S2S-vs-user-API, unit-of-work (SaveChanges in repo), and scope-disposal/N+1 findings are almost always must-fix — fix before requesting review
- Missing integration test findings: the tech lead will always ask. Either add the test (round-trip / access scenario — NOT a unit-logic-path test, which he asks to remove), or pre-empt in the PR description with a linked follow-up ticket
- Cheap pre-empts that recur in his reviews: search endpoints as GET+query, enums/constants instead of raw strings, fail-loud (throw) over silent defaults, Request/Response DTO suffixes, no FQDN in code
- Since mid-2026 the cheapest pre-empts are altitude ones: no product checks, contract as the switch, one pipeline for company+customer scope, few comments, one-ticket PR scope
- Check Mode 2's "Standing decisions" before any architecture proposal; they are newer than the PR-mined patterns
- Cheap pre-empts from Slack:
  - every input path returns a 4xx, never a 500;
  - `inserted_at` on every new table;
  - `required` keyword on DTOs;
  - lowercase plural routes;
  - a new appsetting in all three places;
  - a data migration bumps `UpdatedAt`;
  - no tokens or identity numbers in logs.
