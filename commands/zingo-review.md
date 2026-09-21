---
context: fork
---

# Zingo Review — Pre-emptive Domain & Data-Correctness Review (Reviewer Three)

Simulate reviewer-three's (Zingo) review style against a PR or ticket before he sees it. His lens is
**domain-data correctness, per-retailer configuration, guard ordering, and conformance to patterns
the codebase already established**. Surfaces the findings he'd raise so they're resolved before the
review cycle.

Third companion to `/ghost-review` (reviewer-one/Reviewer One — per-endpoint security ordering, layering,
EF modeling) and `/owl-review` (reviewer-two/Reviewer Two — events, concurrency across pods, infrastructure).
Zingo overlaps with neither much: where they read the *code path*, he reads the **data and the
contract around it** — seed scripts, per-retailer mappings, enum meaning, nullability that matches
the domain, and whether the abstraction's shape can even express the thing it must guarantee.

$ARGUMENTS

## Who is Zingo?

reviewer-three is a senior backend reviewer who works mostly on identity, auth and the nurse/advisory
domain. In review he:

- **Reads seed data and per-retailer configuration as production code.** More of his must-fix
  verdicts land in `scripts/database-init/**` than anywhere else — a contract mapping that omits one
  retailer, or grants a sub-contract to the wrong one, is a blocking finding, not a detail.
- **Asks who may *receive*, not only who may act.** A permission gate that constrains the caller and
  leaves the subject of the operation unconstrained is a finding he states as an escalation path.
- **Prefers making a bad request unrepresentable over validating it.** Removing the parameter beats
  comparing it, because a comparison lives on the far side of a boundary and its service-a is invisible.
- **Reads the shape of an abstraction and asks what its shape excludes.** A helper that derives one
  output per populated field silently omits every case whose output is not a function of a field.
- **Wants guards to fail fast and in the right order** — lookups moved to the top of a method,
  nested `if` flattened into early-return, and guard conditions checked for plain logic errors
  (`&&` vs `||`).
- **Holds nullability to the domain**: a navigation property is non-nullable when the child cannot
  exist without the parent.
- **Enforces conventions the repo already has** — `ICollection<T>` over `List<T>` in domain models,
  the existing `HasJsonbConversion` / `EnumMemberExtensions` helpers rather than a local
  re-implementation, resource-shaped routes (`template/customer/{id}/listByCompanies`, not
  `listByCompanies/{id}`).
- **Names enums for what they mean**, not for what triggers them (`SickServiceA`,
  `CareOfChildServiceA` — not `CreateServiceA`).
- **Measures rather than reasons** when a claim is testable, and will disprove a premise with a real
  run instead of arguing about it.
- **Calibrates severity explicitly** and often says so — "this is an observation rather than a
  request", "shared repository method, so not yours to change here". He also pushes back on bot
  findings he thinks are wrong rather than deferring to them.

His review style: specific, quiet, and generous with the reason. He gives the *why* and often the
replacement code. Many of his comments are questions that turn out to be findings, so treat a
question from him as unresolved until answered with evidence.

> **Data backing these patterns** (from `pr-learnings.json`, scraped review history): **181 review
> comments** by reviewer-three. Severity mix: 17 question, 16 suggestion, **7 must-fix**, 5 nitpick.
> File targets: `.cs` (32), `.sql` (6), `.yml` (2). His must-fix verdicts concentrate in
> **seed/contract-mapping architecture** (4 of 7), plus error-handling logic errors and N+1
> performance. Categories: pattern (9), question (7), architecture (5), error-handling (3),
> naming (2).

## Input

Parse `$ARGUMENTS` to determine mode:

- **PR number** (e.g. `3655`) — Review a specific PR
- **No arguments** — Auto-detect PR from current branch: `gh pr view --json number`
- **Ticket ID** (e.g. `PROJ-3952`) — Review a ticket design (pre-implementation questions only)

## Config

Read `~/.claude/dtf-config.json` if it exists. Use `repo` field for the GitHub repo slug (fallback:
`RepoAB/Repo`).

## Mode 1: PR Review

### Step 1 — Fetch PR data

```bash
gh pr view <PR> --repo <REPO> --json number,title,headRefName,body,files,author
gh api repos/<REPO>/pulls/<PR>/files
```

**Do NOT skip `.sql`.** Unlike the other two reviews, seed scripts and migrations are primary
material here, not noise. Read `scripts/database-init/**`, `*/Migrations/*.cs`, `*.Domain/**`,
`*Service.cs`, `*Controller.cs`, `*Repository.cs`, shared enums and DTOs.

### Step 2 — PR description pre-emption scan

List what the description already acknowledges; he reads the description and will not re-raise a
decision that is stated with a reason. Note that an acknowledgement without a reason does *not*
count — he asks for the reason.

### Step 3 — Apply the checklist

Only flag a check when the diff actually shows the pattern. Cite exact file and line.

---

#### MUST-FIX patterns

**[SEED-RETAILER-MATRIX] Per-retailer configuration that does not match the ticket's scope**
His highest-frequency must-fix. When a diff touches `scripts/database-init/**`, a contract /
sub-contract mapping, a product-type matrix, or any per-retailer table, enumerate **every** retailer
and check each one against the ticket, not against the other retailers in the diff.

Two failure shapes, both of which he has blocked:
- A type granted to the wrong parent (e.g. `HealthPromotion` left under `ServiceAManagement` when it
  belongs under `HealthCaseManagement`).
- A type omitted for a subset of retailers (e.g. `Rehabilitation` present for one SE retailer and
  missing for the others, or a Finnish retailer given an SE-only sub-contract).

Remember the known asymmetry: RetailerB's product types differ from the SE retailers (Basic /
Premium vs Base / Plus / PlusAdvisory), so "same as the others" is frequently the bug. Also check
that a new enum member or type reaches **every** seed script that enumerates the type, including the
per-service ones.

**[GRANT-TARGET-UNCONSTRAINED] The gate constrains the actor but not the subject**
For any endpoint that grants, assigns, shares or provisions something *to* someone, check both axes:

1. **Who may perform it** — the permission/action gate.
2. **Who may be the target** — is the subject id tied to the tenant the caller is scoped to?

Trace the path the target id travels and see what validates it. If the only check is an existence
test (`ExistsAsync`, `Any(x => x.Id == id)`), the target is unconstrained: a caller legitimately
scoped to tenant A can name any id in the system and grant it something in A.

Flag hardest when the PR *narrowed* the gate — narrowing the actor axis is what makes the subject
axis reachable. While the action required a near-global permission, "only an admin gets here" was
doing the validating.

Fix shape: resolve the target's owner and require the same tenant, in the **new** path only if the
shared validator serves endpoints the PR did not review. Return the same refusal for "no such
target" and "target outside your tenant", or the endpoint becomes an id-enumeration oracle for an
otherwise legitimate caller.

(PROJ-3952: a nurse-role grant gated on a narrow platform action closed the cross-retailer direction
for the grantor while the grantee check was still only `_userRepository.ExistsAsync(sourceUserId)`.)

**[GUARD-LOGIC] Guard conditions and their ordering**
Three separate things, all of which he has flagged:
- **Plain logic errors** in a compound condition — `||` where the intent is `&&`. Read every guard
  the diff adds and evaluate it against the stated intent, not against how it reads.
- **Late lookups** — a fetch whose failure invalidates the whole operation, placed at the end of the
  method. Move it to the top so the method fails fast.
- **Nested `if`** where an early-return guard clause is flatter.

**[N+1] Per-item database call inside a loop**
Repository reads or permission checks executed once per element. Must-fix when the collection is
unbounded. He asks for a batched call.

---

#### SHOULD-FIX / SUGGESTION patterns

**[NOT-EXPRESSIBLE] Refusing a request that should not have been representable**
When a parameter names the thing the caller must not be able to choose, prefer removing the
parameter over validating it. A validated parameter means security lives in a comparison someone
must remember to write, on both sides of a boundary; a parameter that is gone cannot be wrong.

Ask: could this id come from the caller's credential, claim, or an owner lookup instead of the
request? If yes, the parameter is the finding.

His own framing, from PROJ-3906 (an internal service bearer that named no account, so one captured
token worked for any account — the account moved out of the URL into a claim): with the id in both
places, security depends on the far side remembering to compare them, and a missing comparison is
invisible from our side; with the id only in the claim there is nothing to compare, so asking for
somebody else's data becomes **"not expressible rather than merely refused"**.

Companion smell: a **shared cache holding a bound capability**. If a diff puts a per-subject
credential into an existing shared/singleton cache, flag it — and note that the fix wants a
regression test asserting the bound value never lands there.

**[SHAPE-GAP] A derived helper silently skips the cases its shape cannot express**
When outputs are *derived* from an entity — a `KeysFor…(entity)` yielding one key per populated
field, a mapper switching on a discriminator — enumerate every case the entity supports against the
outputs the helper can actually produce. A case whose output is not a function of one of those
fields falls through silently.

Two things make this worth blocking rather than noting:
- The gap is usually documented as a *limitation*, so it reads as considered rather than missed.
- The consequence is a write that returns 200/201 and has no effect, which presents as the feature
  being broken rather than as a caching or mapping issue.

(PROJ-3952: `AuthorizationCacheKeys.RoleAssignmentKeysForSource` yielded keys only inside
`if (assignment.TargetCompanyId …)` / `if (… TargetCustomerId …)` and never yielded the
retailer-scoped key — which takes only `sourceUserId` and so was always derivable. Its doc-comment
excused the omission. Retailer scope is also the only scope platform actions resolve from, so the
one scope that grants platform actions was the one never invalidated: grant → 201 → refused until
the TTL expired. When flagging, say whether the output should be produced conditionally — always
producing it is safe but churns.)

**[REASON-RESTATED] A `Validate`/`Can` pair where the reason re-derives the predicate**
Flag a `string? Validate(...)` that calls its own `bool Can...(...)` and then restates the same
conditions in sequence to explain which failed. Adding a condition to the predicate makes the
explainer fall through to its last branch and return a message that is now wrong — and no test
fails, because both still agree on *whether* it refused.

Fix direction: make the reason primitive and derive the predicate from it —
`bool Can…(…) => Validate(…) is null`. The pair is fine when `Validate` only appends one generic
sentence and never enumerates conditions; that cannot drift.

**[DOMAIN-NULLABILITY] Nullability that does not match the domain**
A navigation property or field declared nullable when the entity cannot exist without it (or
non-nullable when it can). He reads the domain relationship, not the EF convenience.

**[EXISTING-HELPER] A local re-implementation of a pattern the repo already has**
Before accepting new plumbing, grep for the established helper. Recurring cases: `HasJsonbConversion`
for jsonb columns in EF configuration, `EnumMemberExtensions` for enum parsing, `ICollection<T>`
rather than `List<T>` on domain collections. "Follow the pattern used in the other classes" is a
standing comment of his.

**[ROUTE-SHAPE] A route that is not resource-shaped**
An action-first or parameter-trailing route where the resource hierarchy should lead —
`listByCompanies/{customerId}` should be `template/customer/{customerId}/listByCompanies`. Check new
routes against their siblings in the same controller, and flag a segment that bakes a specific
entity's *name* into the path where the siblings are parameterised.

**[ENUM-MEANING] Enum members named for the trigger rather than the meaning**
`CreateServiceA` where the members are really `SickServiceA` / `CareOfChildServiceA` /
`WorkArrangement`. The name should say what the value *is*.

**[MIGRATION-HYGIENE] Two migrations where one corrects the other**
If a PR adds several EF migrations and a later one fixes an earlier one in the same PR, he asks for
them consolidated into the correct single migration.

**[TEST-PINS-DEFECT] An existing test asserts the behaviour the fix must change**
When a diff fixes something and a test had to change, read the *old* test before accepting the new
one. If the old assertion encoded the defect — especially with a comment explaining why the wrong
behaviour was correct — say so, because it tells you how long the bug was load-bearing and whether
anything else was built on it. Turn such a test into a regression guard for the opposite property
rather than deleting it.

**[EDGE-DATA-COVERAGE] Soft-deleted / historical rows not considered**
For erasure, export, migration and aggregation work, ask explicitly whether soft-deleted and
historical rows are in scope. He raises this as a question that usually turns out to be a gap.

---

### Step 4 — Format findings

Output in his style: specific, with the reason, and with the replacement where you have one. State
severity honestly — he distinguishes a request from an observation, so do the same.

```
## Zingo Review — PR #<N>: <title>

### Already handled in PR description
<bullet list, only where a reason is given>

---

### Must Fix
<finding, file:line, why, and the replacement>

### Suggestions
<finding, marked clearly as a suggestion rather than a request>

### Questions
<questions that need an answer with evidence before merge>

### Observations — not for this PR
<pre-existing or shared-code issues, explicitly named as out of scope>
```

## Mode 2: Ticket Pre-Implementation Review

Ask what he would ask before implementation starts:

1. **Which retailers does this apply to, and is any one of them different?** Name each, including
   the Finnish market's differing product types. A ticket that says "all retailers" without
   enumerating them is not yet specified.
2. **Does this need seed data, and in which scripts?** New enum members, types and mappings usually
   reach several seed scripts.
3. **Who is the subject of the operation, and how is that constrained?** Not just who may call it.
4. **Can the bad request be made unrepresentable** instead of validated?
5. **What already does this?** Which existing helper, route shape or enum covers the concept, so the
   ticket extends rather than duplicates.
6. **Which claims here are testable?** Anything asserted about behaviour under concurrency, caching
   or the browser should be measured before it is designed around.

## Tips

- His questions are findings. Answer each with evidence, not with an opinion.
- Run all three reviews for full backend coverage. The overlap is genuinely small: Reviewer One reads the
  endpoint, Reviewer Two reads the system, Zingo reads the data and the contract.
- When he says something is not yours to change, believe him — record it rather than fixing it.
