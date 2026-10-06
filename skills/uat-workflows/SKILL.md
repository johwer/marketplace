---
name: uat-workflows
description: UAT testing workflows — acceptance criteria validation, structured bug reporting, permission testing, and business rule verification for Repo
---

## UAT Execution Workflow

### Phase 1: Preparation
1. **Read the ticket** — understand what was built and why
2. **Check acceptance criteria** — list every testable criterion
3. **Identify test users** — which roles need testing?
4. **Prepare test data** — do we need specific companies, employees, cases?

### Phase 2: Systematic Testing
For each acceptance criterion:
1. Test the **happy path** first (does it work as described?)
2. Test **edge cases** (empty fields, max values, special characters)
3. Test **permissions** (each user role separately)
4. Test **cross-browser** if UI change (Chrome, Safari at minimum)
5. Test **mobile responsiveness** if relevant

### Phase 3: Documentation
- **Pass**: Mark criterion as verified with date and tester
- **Fail**: Create structured bug report (see template below)
- **Unclear**: Add comment asking for clarification on the ticket

### Phase 4: Sign-off
- All criteria verified → comment "UAT Approved" on ticket
- Blocking issues → comment "UAT Blocked" with links to bug tickets
- Minor issues → comment "UAT Approved with notes" listing non-blocking findings

## Permission Testing Matrix

### Repo Role Hierarchy
```
System Admin
  └── Company Admin
       ├── HR Administrator (full company scope)
       │    └── Limited HR (department scope only)
       ├── Case Handler
       │    └── Limited Case Handler
       ├── ServiceE Viewer
       └── Employee (own data only)
```

### What to Test per Role
| Check | Admin | HR Admin | Limited HR | Employee |
|-------|-------|----------|------------|----------|
| View all employees | Yes | Own company | Own dept | No |
| View service-a reports | Yes | Own company | Own dept | Own only |
| Create service-a report | Yes | Yes | Yes | Own only |
| View service-e | Yes | If permitted | If permitted | No |
| Manage users | Yes | If permitted | No | No |
| View case details | Yes | If permitted | No | Own only |

### Permission Test Script
For each feature under test:
```
1. Log in as System Admin → verify full access
2. Log in as HR Admin (Company A) → verify company-scoped access
3. Log in as HR Admin (Company B) → verify NO access to Company A data
4. Log in as Limited HR (Dept X) → verify department-scoped access
5. Log in as Employee → verify own-data-only access
6. Log out → verify login redirect (no anonymous access)
```

## Structured Bug Report Template

```markdown
## UAT Finding: [One-line summary]

**Parent ticket:** PROJ-XXXX
**Environment:** Accept (staging)
**Tested by:** [Name]
**Date:** [YYYY-MM-DD]
**Browser:** Chrome 120 / Safari 18

### Steps to Reproduce
1. Log in as [role] with user [test-username]
2. Navigate to [URL or menu path]
3. Click [element / button]
4. Enter [specific data if relevant]
5. Observe [what happens]

### Expected Behavior
[What the acceptance criteria says should happen]

### Actual Behavior
[What actually happened — be specific]

### Impact
- **Affected roles:** [Admin, HR Admin, Employee, etc.]
- **Severity:** Critical / High / Medium / Low
- **Frequency:** Always / Sometimes / Rare
- **Blocking release:** Yes / No
- **Workaround available:** Yes (describe) / No

### Evidence
- Screenshot 1: [description — attached]
- Screenshot 2: [description — attached]
- Video: [if complex flow — attached]

### Additional Context
[Any relevant details: specific test data, timing, sequence dependency]
```

## UAT Checklist for Common Repo Features

### ServiceA Report Feature
- [ ] Employee can create a new service-a report
- [ ] Required fields are validated (start date, type)
- [ ] HR Admin can see the report in their company view
- [ ] Case is auto-created if service-a exceeds threshold
- [ ] Notification email sent to relevant parties
- [ ] ServiceE updated correctly

### User Management Feature
- [ ] Admin can invite new user
- [ ] Correct roles are assignable
- [ ] User receives invitation email
- [ ] New user can log in and see correct scope
- [ ] Removing a role immediately restricts access
- [ ] Multi-company users see correct company switcher

### ServiceE/Dashboard Feature
- [ ] Data matches known test data
- [ ] Filters work correctly (date range, department, company)
- [ ] Export produces correct file (CSV/Excel)
- [ ] Widgets show correct authorization
- [ ] Loading states display properly
- [ ] Empty states show helpful message

## Jira Commands for UAT

```bash
# View ticket details
acli jira workitem view PROJ-1234

# Add UAT finding as comment
acli jira workitem comment PROJ-1234 "UAT Finding: [description]. See bug ticket PROJ-5678."

# Create a bug ticket (a real subtask of the feature under test when it is an open story)
acli jira workitem create --project PLRS --type Bug --summary "UAT: [description]" --description "[full report]"
acli jira workitem create --project PLRS --type Subtask --parent PROJ-1234 --summary "UAT: [description]" --description "[full report]"

# Assign and point it (--assignee fails; points 1-4 per the story-points skill)
bash ~/.claude/scripts/jira-assign.sh PROJ-5678
bash ~/.claude/scripts/jira-set-field.sh PROJ-5678 customfield_10437 2

# Link bug to the feature, then READ IT BACK: the direction often comes out reversed
acli jira workitem link create --out PROJ-5678 --in PROJ-1234 --type Relates
acli jira workitem view PROJ-1234 --fields issuelinks --json | jq '.fields.issuelinks[] | {type: .type.name, out: .outwardIssue.key, in: .inwardIssue.key}'

# Download test evidence (screenshots from ticket)
bash ~/.claude/scripts/jira-download-attachments.sh PROJ-1234

# Transition ticket status
acli jira workitem update PROJ-1234 --status "UAT Approved"
```

## Test Environment Reference

| Environment | URL | Purpose |
|-------------|-----|---------|
| Dev | (local) | Developer testing |
| Accept | accept.repo.se | UAT / staging |
| Production | app.repo.se | Live |

### Test Users (Accept)
Check with team for current test user credentials. Never hardcode passwords — use environment variables or password manager.
