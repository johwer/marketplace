# ServiceC: resolver methods, platform actions, TT naming

DTF's copy of three sections that `services/ServiceC/AGENTS.md` dropped in #4470 (PROJ-4795, `28840783b`).
The repo now keeps a four-bullet summary in `.claude/rules/service-c-permissions.md`; read that first and
use this file for the detail it no longer carries. Copied verbatim from
`git show 620450c1:services/ServiceC/AGENTS.md`. Before relying on a file or method named here, grep it
on `origin/main`: this copy does not follow the code.

## Permission Resolver Methods

The `PermissionResolver` has nine methods that map permissions to actions. Each method determines **which assignment scopes** grant the action:

**User/Company permission methods:**

| Method | Permission→Action Mapping | Assignment Scopes Where Mapping Is Considered |
|--------|---------------------------|-----------------------------------------------|
| `resolver.User(UserPermission, UserAction)` | `UserPermission → UserAction` | **All scopes**: User, Tag, Company, Customer and Retailer. A company-scoped assignment grants the action on every user in the company |
| `resolver.Tag(UserPermission, UserAction)` | `UserPermission → UserAction` | **Tag**, **Company**, **Customer** and **Retailer**; NOT user-scoped |
| `resolver.Company(CompanyPermission, CompanyAction)` | `CompanyPermission → CompanyAction` | **Company**, **Customer**, and **Retailer** scopes (company-level assignments only; NOT user- or tag-scoped) |
| `resolver.CompanyUsers(CompanyPermission, UserAction)` | `CompanyPermission → UserAction` | **Company**, **Customer**, and **Retailer** scopes granting user-targeted actions within the company |
| `resolver.UserCompany(UserPermission, CompanyAction)` | `UserPermission → CompanyAction` | **All scopes**, including **User** and **Tag**; user-/tag-scoped assignments can grant a company-level action |
| `resolver.TagCompany(UserPermission, CompanyAction)` | `UserPermission → CompanyAction` | **Tag**, **Company**, **Customer** and **Retailer**; NOT user-scoped |

**Customer permission methods:**

| Method | Permission→Action Mapping | Assignment Scopes Where Mapping Is Considered |
|--------|---------------------------|-----------------------------------------------|
| `resolver.Customer(CustomerPermission, CustomerAction)` | `CustomerPermission → CustomerAction` | Customer-scoped assignments |
| `resolver.CustomerCompany(CustomerPermission, CompanyAction)` | `CustomerPermission → CompanyAction` | Customer-scoped assignments granting company-level actions |
| `resolver.CustomerUsers(CustomerPermission, UserAction)` | `CustomerPermission → UserAction` | Customer-scoped assignments granting user-targeted actions |

**When to use each:**
- **`resolver.User`** — Standard user-targeted actions (read/edit a specific user's data)
- **`resolver.Company`** — Company-level mutations and reads (manage company settings, read company config)
- **`resolver.CompanyUsers`** — Actions on users within a company scope (list users, bulk operations)
- **`resolver.UserCompany`** — Use with caution. Grants `CompanyAction` for ALL assignment scopes including user-scoped. Appropriate for read-only company actions derived from user permissions (e.g., reading template config when you have service-a view permission). **Do NOT use for company-level mutations** unless elevation from user-scope is explicitly desired.

_Source: PROJ-2180_

## Granting a Platform Action

**`PlatformAction` is the one action kind that never enters `PermissionResolver`.** The table above
does not cover it, and looking for its mapping site is a dead end — `ActionsMap` composes only the
customer/company/user mappings, so there is no `Permission → PlatformAction` row to add anywhere.

The entire registration surface is:

1. The enum member in `shared/Repo.Shared.Models/Enums/PlatformAction.cs`.
2. A `role_global_permissions` row carrying the action in its `authorized_platform_actions` jsonb array.
3. A role assignment with a **non-null `target_retailer`**.

Step 3 is the one that gets missed. `ListPlatformActionsAsync` filters on `ra.TargetRetailer != null`
(`AuthorizationService.cs`), and `RoleGlobalPermissions` says so in its own doc-comment: *"only
applicable to retailer-scoped assignments"*. **A platform action granted to a company-scoped or
customer-scoped role resolves to nothing.** The grant looks correct in the database and the user is
still refused, with no error anywhere to explain it.

Three consequences worth knowing before you design around this:

- **A platform action cannot be granted to a `RoleType`.** Grants attach to a role *row*, not a role
  *type*, so "give this to `MedicalStaff`" is not expressible — you grant it to a specific
  retailer-scoped role that happens to be of that type. A ticket phrased the first way needs
  rewording before it can be implemented.
- **Every global platform admin holds every platform action automatically.** `GlobalAdminActions.PlatformActions()`
  is `Enum.GetValues<PlatformAction>()`, so a new member is granted to all of them the moment it is
  added. That also means a global-admin account proves nothing when you are testing a grant — use a
  non-admin.
- **A platform action check is retailer-agnostic.** `CanUserDoPlatformAction` unions the actions of
  *every* retailer-scoped assignment the caller holds (`ListPlatformActionsAsync`). Holding the action
  on one retailer passes the check for all of them. An endpoint that gates on a platform action but
  writes data scoped to one retailer also needs a check on that specific retailer (as
  `AssignToRetailer` does with `RetailerAssignRoleScope`), or must derive the retailer instead of
  taking it as a parameter.

**Testing gotcha:** role assignments are cached in **Redis**, not in-process, so hand-editing a grant
in the database appears to have no effect *even across a container restart*. If the API contradicts
the database, suspect the cache before the code:

```bash
docker exec repo-redis redis-cli DEL "service-c:service-c:role_assignments:<userId>_retailer_scoped"
```

_Source: PROJ-3684_


## TT vs Repo Permission Naming

TT (RetailerB) permissions use a "TT " prefix to distinguish them from Repo permissions (e.g., "TT View Case" vs "View Case"). When creating new permissions:

- Always create TranslationService translation keys for new permission names
- The `humanizePermission()` fallback splits on every capital letter, producing broken labels (e.g., `TTViewCase` becomes "T T View Case")
- Never rely on `humanizePermission()` for display — always have a TranslationService key

_Source: PROJ-2104_

