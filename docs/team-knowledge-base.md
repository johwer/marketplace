# Team Knowledge Base — Pushback & Improvement Tracker

Living document for knowledge gaps, recurring issues, communication improvements, and interview findings. Used by `/ticket-refine` to inform pushback and by the team to improve ticket quality.

---

## Categories

1. [Ticket Writing](#ticket-writing) — How requirements are communicated
2. [Domain Knowledge](#domain-knowledge) — Business logic gaps the team needs documented
3. [Permissions & Roles](#permissions--roles) — Role permutations, access control, naming
4. [Cross-Service Understanding](#cross-service-understanding) — What happens across services
5. [Performance](#performance) — Known bottlenecks and architectural concerns
6. [Testing & UAT](#testing--uat) — QA process, old vs new system alignment
7. [Visualization & Navigation](#visualization--navigation) — Page visibility, permission-based UI

---

## Ticket Writing

### Requirements describe WHAT, not HOW
- **Problem:** Tickets state the desired outcome but not the expected behavior or constraints
- **Impact:** Developers make assumptions that don't match business intent
- **Fix:** Tickets should include: expected behavior per role, edge cases, error states, and acceptance criteria with concrete examples
- **Example pushback:** "This ticket says 'add manager approval' but doesn't specify: Which roles can approve? What happens if the manager is absent? Can approval be revoked?"

### Domain knowledge not written down
- **Problem:** Critical business rules live in people's heads, not in tickets or documentation
- **Impact:** AI team and new developers can't reason about correctness without tribal knowledge
- **Fix:** Create a domain glossary. Every ticket that introduces or modifies a business concept should reference or update it
- **Action:** Interview team members (see [Interview Log](#interview-log)) to extract and document domain rules

---

## Ticket Author Profiles

> **Source of truth**: `~/.claude/team-profiles.json`
> Author profiles, tech leads, pushback levels, and ticket flow are all stored in the config file.
> `/ticket-refine` reads this file automatically. `/scrape-jira-pushback` updates it with data from real tickets.

**Quick reference** (see `team-profiles.json` for full details):

| Author | Role | Pushback | Key pattern |
|--------|------|----------|-------------|
| Monika Åkvist-Johansson | tester (upstream) | n/a | Finds UAT issues, flows through others |
| Andreas Höjevik | tester | **HIGH** | Thin 1-2 sentence tickets, title/desc mismatch |
| Ludvig Övergaard | product | **MEDIUM** | Good product specs, lacks technical context |
| Dennis Vinterfjärd | tech_lead | **LIGHT** | Validates others' tickets, trust his intent |

**Key rules:**
- High-pushback author + no tech lead comment = **HIGH RISK** flag
- Tech lead comment on any ticket = partially validated
- Run `/scrape-jira-pushback` periodically to update profiles with real data

---

## Domain Knowledge

### Gaps to document (from Zingo pushback session)

| Area | What's missing | Who knows | Status |
|------|---------------|-----------|--------|
| ServiceA types | Full list of service-a types, how they interact, which are mutually exclusive | ? | TODO |
| Manager-employee relationship | All permutations of manager-to-employee connections and what each enables | ? | TODO |
| Permission model | Complete mapping of permissions to features/pages/actions | ? | TODO |
| ServiceB service scope | What ServiceB owns vs other services, boundaries | ? | TODO |
| TT migration | What changed, what's carried over, data mapping from old to new | ? | TODO |
| Service event flows | What happens in each service when a user/service-a is created or updated | ? | TODO |

---

## Permissions & Roles

### Role permutations need clearer naming
- **Problem:** "Chef-koppling" (manager connection), roles, and permissions are conflated. Technical naming doesn't match how users think about it
- **Impact:** Tickets use vague terms like "the manager should see this" without specifying which type of manager relationship or permission
- **Fix:** Create a permission matrix: Role x Feature x Action = Allowed/Denied
- **Known complexity:**
  - Manager connection types (direct, delegated, temporary?)
  - Role vs permission distinction (a role grants permissions, but tickets mix the terms)
  - Late role changes — roles change in reality but the system assumes static assignments
  - User perspective vs technical implementation often diverge

### Permission type permutations
- **Problem:** The full set of permission combinations is not documented anywhere
- **Impact:** Tickets assume "obvious" permission behavior that differs between team members' mental models
- **Fix:** Enumerate all permission types with concrete examples of what each allows

### Which pages are visible per role
- **Problem:** No single reference for "if I have role X, which pages/features can I see?"
- **Impact:** Impossible to verify completeness of permission-gated UI without manual testing
- **Fix:** A permission key/matrix that maps roles to visible pages — could be auto-generated from C# permission attributes if all services have consistent patterns

---

## Cross-Service Understanding

### What happens across services on create/update
- **Problem:** When a user or service-a is created/updated, events flow through multiple services. No one document describes the full chain
- **Impact:** Changes in one service break assumptions in another. Developers don't know what side effects their changes trigger
- **Fix:** Document the event flow: User creates X -> Service A does Y -> publishes event Z -> Service B does W
- **Key flows to map:**
  - Create user -> ServiceB, TT, and other services
  - Create/update service-a -> which services react?
  - Permission change -> what gets invalidated?

### 4 backend calls + 4 bus messages = performance concern
- **Problem:** Some operations trigger 4 backend API calls plus 4 messages on the service bus
- **Impact:** Slow user experience, potential timeout/ordering issues
- **Fix:** Map which operations have this pattern. Consider: Can calls be parallelized? Can bus messages be batched? Is all of this necessary?

---

## Performance

| Pattern | Description | Severity | Status |
|---------|-------------|----------|--------|
| Backend + bus fan-out | 4 API calls + 4 bus messages for single user action | Medium | Needs investigation |

---

## Testing & UAT

### Old system vs new system alignment
- **Problem:** UAT/bug testing (Monika, Ludvig, Andreas) — unclear if current behavior matches or intentionally deviates from the old system
- **Impact:** Bugs get reported that are actually intentional changes, and real regressions get missed
- **Key questions:**
  - How does the new system work compared to the old one? Where does it intentionally differ?
  - Is the current behavior aligned with what Dennis has designed/approved?
  - Do UAT testers have a reference for "expected behavior" or are they comparing from memory?
- **Fix:** Create a comparison document for areas that changed. Mark each difference as: Intentional / Bug / Needs Decision

---

## Visualization & Navigation

### Feature idea: Permission Debug Overlay (like translation key toggle)

Similar to the existing translation key display mode, add a toggleable overlay that shows permission and action metadata directly on the UI. Only visible for CS/dev roles — not end users.

**Concept:**
- A toggle (like the translation key toggle) that activates "permission mode"
- When active, UI elements show what permissions/actions are attached to them
- Display format options (investigate what works best):
  - Tooltip on hover — shows required permission/action for that button/element
  - Badge/tag overlay — small label next to each interactive element
  - Side panel — list of all actions on the current page with their permission requirements
  - Color coding — elements colored by permission group

**Two layers:**
1. **Element-level actions** — "This button requires `service-a.approve` permission" — shows which user actions are gated and by what
2. **Page-level visibility** — "This page requires `employee.read` + `manager` role" — shows which roles can even see this page

**Why this matters:**
- CS can verify "why can't user X see button Y?" without asking a developer
- Developers can verify permission coverage when building new features
- Testers can check if permission gates match the ticket requirements
- During ticket refinement, we can reference actual permission names instead of vague "manager should see this"

**Feasibility investigation (completed 2026-03-06):**

Findings:
- Translation key toggle: localStorage flag (`translationKeysOption`) + i18next post-processor + language dropdown option. Clean pattern to copy.
- Permissions are checked via two consistent systems:
  1. Feature flags: `authorizedFeatures.hasDashboard` etc. in `AuthContext` — gates pages/routes via `FeatureGuard`
  2. Action permissions: `useActionAuthorization().can({ userActions: [UserAction.X] })` — gates buttons/elements. 77 user + 51 company + 20 customer actions.
- Both systems are centralized and consistent — no scattered patterns.
- Key files: `AuthContext.tsx`, `ActionAuthorizationProvider.tsx`, `FeatureGuards.tsx`, `service-cApi.ts` (enums), `authorizedFeatures.ts` (route mapping)

**Implementation plan (two tickets drafted):**

Ticket 1 — Tier 1 + 2 (2-3 points):
- localStorage toggle (`permissionDebugMode`) + Feature Flags page toggle
- Side panel/drawer showing: page-level feature flags + action-level checks with results
- Intercept `can()` function to collect debug data — minimal code change (2-3 files)
- No per-component changes needed

Ticket 2 — Tier 3 (3-4 points):
- "View as role" simulation — dropdown to preview UI as different roles
- Color-coded elements by permission state (granted/denied/unchecked)
- Per-element tooltip showing required action on hover
- Filtering/search within the debug panel

**Jira tickets:**
- PROJ-1999 — Tier 1+2: Page-level panel + route matrix + action tracking (2-3 pts)
- PROJ-2000 — Tier 3: Role simulation + element tooltips + color coding (3-4 pts, depends on PROJ-1999)

### Permission matrix (static reference)
- **Problem:** No single reference for "if I have role X, which pages/features can I see?"
- **Impact:** Impossible to verify completeness of permission-gated UI without manual testing
- **Fix (short term):** Generate a static role-to-page matrix from C# permission attributes. Even a spreadsheet would help.
- **Fix (long term):** The permission debug overlay (tickets drafted) replaces the need for a static document

---

## Interview Log

Template for knowledge-extraction interviews with team members.

### Interview template

```
INTERVIEW — [Person] — [Date]
==============================

Topic: [What area are we exploring]
Duration: [Approx time]

KEY FINDINGS
------------
1. [Finding — stated as a fact or rule]
2. [Finding]

GAPS IDENTIFIED
---------------
- [Something they couldn't answer or was unclear]

CONTRADICTIONS WITH OTHER INTERVIEWS
-------------------------------------
- [Where this person's understanding differs from others]

ACTION ITEMS
------------
- [ ] Document [X] in domain glossary
- [ ] Create ticket for [Y]
- [ ] Update knowledge base with [Z]
```

### Completed interviews

| Person | Date | Topics | Key findings |
|--------|------|--------|-------------|
| Zingo | 2026-03-06 | Pushback, requirements quality, permissions, cross-service | Initial observations — see notes above |

---

## How to use this document

- **During `/ticket-refine`**: Check if the ticket touches any known gap areas. If it does, flag it and reference the specific gap
- **During sprint planning**: Review open gaps — are any blocking upcoming tickets?
- **After interviews**: Add findings, update gaps, mark resolved items
- **Recurring patterns**: When the same pushback appears 3+ times, escalate it as a process change proposal
