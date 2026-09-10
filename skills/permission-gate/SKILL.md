---
name: permission-gate
description: Hard stop before writing authorization code in Repo. Answers "does this permission/role/action already exist" from the real ServiceC model in five lines, then forces at most three decisions before implementation continues. Use when a ticket, plan or diff touches Permission, Action, Role, RoleType, scope, [Authorize], CanUserDo*, ServicePermissionMap, or a frontend feature gate. Not an interview — it greps first and asks only what the code cannot answer.
user_invocable: true
---

## Why this is a gate and not a nudge

Nearly every authorization mistake at Repo is the same mistake: someone needed a
capability, could not see that it already existed, and added a new one. NOVA-3172 is the
canonical case, and `docs/authorization-surfaces.md` already records the ruling that came
out of it:

> reuse the existing write action for whatever the page administers. It did not invent a new
> "may configure this" permission, and neither should we — that would mean new permission
> wiring, seeding and migration for no gain.

A new permission is never a local change. It touches the enum, both mapping files, the
assignable set, seeding, migration and the frontend gate. So the default answer is **reuse**,
and the burden of proof sits on the person adding one.

## Trigger

The plan or the diff mentions any of: `UserPermission`, `CompanyPermission`, `CustomerPermission`,
`UserAction`, `CompanyAction`, `CustomerAction`, `PlatformAction`, `RoleType`, `RoleAssignment`,
scope, `[Authorize]`, `CanUserDo`, `ServicePermissionMap`, `AuthorizedFeature`, or a `has*` /
`can*` visibility gate in `apps/web`.

Run it **before** implementation, at the same point as the domain model gate. Running it after
the code exists means you are defending a choice instead of making one.

---

## Step 1 — Read the map before you grep (2 min)

These already exist. Do not rebuild them, and do not summarise them into a new document.

| What you need to know | Where it is |
|---|---|
| Which page/tab is revealed by which action, and whether that action is overloaded | `docs/authorization-surfaces.md` — PO-readable, 699 lines |
| The consumption vs administration test (read reveals vs write reveals) | same file, "The test applied to each surface" |
| Resolver method semantics, and how a **PlatformAction** grant is actually made | `services/ServiceC/CLAUDE.md` — "Permission Resolver Methods", "Granting a Platform Action" |
| TT vs Repo permission naming | `services/ServiceC/CLAUDE.md` — "TT vs Repo Permission Naming" |

## Step 2 — Locate the concept in the model

The model has three layers. Grep the *concept*, not the name you were about to invent — a
name is not a reference.

**Permissions** (what a role holds) — `services/ServiceC/ServiceC.Domain/Models/Permissions/`
`UserPermission.cs` (~60) · `CompanyPermission.cs` (~14) · `CustomerPermission.cs` (~4)

**Actions** (what code checks) — `shared/Repo.Shared.Models/Enums/`
`UserAction.cs` (~91) · `CompanyAction.cs` (~76) · `CustomerAction.cs` (~41)

**The wiring between them** — `services/ServiceC/ServiceC.Domain/Permissions/`
- `DefaultPermissionsMappings.cs` — Repo retailers (Base, Plus, PlusAdvisory)
- `TTPermissionsMappings.cs` — Terveystalo, `TT`-prefixed permissions, mapped independently
- both registered in `ActionsMap.cs` static constructor, which runs at application start
- `PermissionResolver.cs` — the dictionaries, including the **Tag-scope-only** buckets: a
  `User`-scoped assignment does *not* grant those

Two more layers people forget:

- **Assignability** — holding a mapping is not enough. `ServicePermissionMap.Compose(retailer,
  activeContracts)` decides what a company *may* assign, via
  `ServiceC.API/Services/AssignablePermissionProvider.cs:42`. Terveystalo and the Swedish retailers
  share **no permission values at all**.
- **Runtime** — `AuthorizationService.CanUserDoUserAction` / `CanUserDoCompanyAction` /
  `CanUserDoCustomerAction` (`services/ServiceC/ServiceC.API/Services/Authorization/AuthorizationService.cs:23,82,113`).
  A global admin (`GlobalUserPermissions.GlobalAdmin`) short-circuits every check to `true`, so
  testing as one proves nothing.

**Frontend gate** — `apps/web/src/utils/deriveAuthorizedFeatures.ts` is a hand-synced port of
the backend `AuthorizedFeatureService`. It must change in the **same PR** as the backend rule.
The parity test (`PARITY_CHECK=1`) is opt-in and does **not** run in CI, so nothing will catch
a drift for you.

## Step 3 — Answer in five lines, maximum

Output exactly this shape. No essay. If it does not fit in five lines, you have not found the
answer yet.

```
FINNS         — CompanyAction.HcmTemplateEdit, DefaultPermissionsMappings.cs:212
                already granted by CompanyPermission.ManageHcm. Use it.
FINNS DELVIS  — the action exists but is unmapped for Terveystalo (TTPermissionsMappings.cs)
FINNS INTE    — nothing covers <concept>; adding one costs: enum + 2 mapping files +
                ServicePermissionMap + seed + migration + deriveAuthorizedFeatures.ts
```

## Step 4 — At most three decisions, each with a recommendation

Ask only what the code could not answer. One question at a time, each with the recommended
answer stated up front so it can be waved through in a word.

1. **Reuse or new?** — recommended: reuse. Name the existing permission/action and what breaks
   if it is reused. Only "the existing one grants strictly more than this caller may have" is
   a valid reason to add one.
2. **Consumption or administration surface?** — apply the test from `authorization-surfaces.md`:
   is there anything for a read-only user to do here? If no, the **write** action reveals it.
3. **Which scope?** — User / Tag / Company / Customer / Retailer. If the answer is Tag or wider,
   say explicitly whether a `User`-scoped assignment must *not* grant it; that is the
   Tag-scope-only bucket and it is easy to miss.

If it is a Terveystalo ticket, add: does this need a `TT`-prefixed twin? The two retailers share
no permission values.

## Step 5 — Record the decision, then stop blocking

Write one line into the notes and into the PR body's Decisions section:

> **Permission:** reused `CompanyAction.HcmTemplateEdit` rather than adding
> `ManageHcmTemplates` — the template admin tab is an administration surface (NOVA-3172
> pattern), so the write action reveals it. Scope: Company.

That line is what the reviewer challenges. Without it, the reviewer only sees the code and has
to reverse-engineer the choice.

## Refuse to proceed while

- the answer to "does this already exist" is unknown rather than `FINNS INTE`
- a new permission is proposed with no named reason the existing one cannot serve
- a backend rule changed without `deriveAuthorizedFeatures.ts` in the same diff
- verification was done as a global admin, which passes every check
