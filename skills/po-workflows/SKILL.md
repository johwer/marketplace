---
name: po-workflows
description: Product Owner workflows — ticket refinement, sprint planning, requirements analysis, impact assessment for Repo
---

## Ticket Refinement Checklist

### Before a ticket is READY:
- [ ] Clear user story: "As a [role], I want [goal], so that [benefit]"
- [ ] Acceptance criteria (Given/When/Then format)
- [ ] Edge cases identified and documented
- [ ] UI/UX: mockups or wireframes attached (if applicable)
- [ ] API contract defined (if backend change)
- [ ] Impact on other services identified
- [ ] Data migration needs assessed
- [ ] i18n: translation keys planned (5 languages: sv, en, da, no, fi)
- [ ] Estimated story points (1-4 scale)

### User Story Template
```
As a [HR administrator / employee / system admin],
I want to [specific action],
So that [business value].

**Acceptance Criteria:**
- Given [context], when [action], then [result]
- Given [context], when [action], then [result]

**Out of scope:**
- [What this ticket does NOT include]

**Dependencies:**
- [Other tickets or services needed]
```

## Sprint Planning

### Estimation Scale (Repo convention)
- **1 point** — Simple, well-understood, single file/service change
- **2 points** — Moderate complexity, 2-3 files, one service
- **3 points** — Cross-service, needs design decisions, database changes
- **4 points** — Complex, multiple services, significant risk — consider splitting

### Capacity Planning
- Total team points per sprint: [configurable]
- Buffer for bugs/support: ~20% of capacity
- Max 1 four-pointer per sprint per developer

## Impact Analysis Workflow

When evaluating a feature request:

1. **Identify affected services**
   ```bash
   # Search for related code in the monorepo
   grep -r "EntityName" services/ --include="*.cs" -l
   grep -r "relatedEndpoint" apps/web/src/ --include="*.ts" -l
   ```

2. **Check API contracts**
   - Which endpoints change?
   - Are there breaking changes?
   - Who consumes these endpoints?

3. **Database impact**
   - New tables or columns?
   - Data migration needed?
   - Performance impact on existing queries?

4. **Frontend impact**
   - New pages or components?
   - State management changes?
   - RTK Query API generation needed?

5. **Cross-cutting concerns**
   - Authorization/ServiceC changes?
   - Email/notification templates?
   - Translation keys (TranslationService)?
   - ServiceE/reporting impact?

## Jira Quick Reference

```bash
# View ticket
acli jira workitem view PROJ-1234

# Update ticket status
acli jira workitem update PROJ-1234 --status "In Progress"

# Add comment
acli jira workitem comment PROJ-1234 "Analysis complete — see AC below"

# Download attachments
bash ~/.claude/scripts/jira-download-attachments.sh PROJ-1234
```

## Recommended External Skills

For enhanced product management:
- **Spec-Flow** — AI-powered specification-driven development with Jira/Confluence integration
- **PICT Test Designer** — Pairwise/combinatorial test case generation from requirements
