---
name: testing-workflows
description: QA testing workflows — test planning, E2E with Playwright, regression testing, bug reporting for Repo
---

## Test Strategy

### Test Pyramid
1. **Unit tests** — Fast, isolated, cover business logic (Vitest / xUnit)
2. **Integration tests** — Real database, service-to-service (xUnit + TestContainers)
3. **E2E tests** — Critical user flows in browser (Playwright)
4. **Manual/exploratory** — Edge cases, UX, accessibility

### When to Write Which
- New business logic → Unit test first (TDD)
- API endpoint changes → Integration test
- User-facing feature → E2E for happy path
- Bug fix → Regression test that reproduces the bug

## Frontend Testing (Vitest + Playwright)

### Unit Tests (Vitest)
- Co-located: `ComponentName.test.tsx` next to `ComponentName.tsx`
- MUST import: `import { describe, expect, it } from "vitest"` (CI fails without)
- Test behavior, not implementation — what the user sees/does
- Use `@testing-library/react` for rendering

### E2E Tests (Playwright)
- Location: `apps/web/e2e/`
- Use Page Object Model pattern
- Stable selectors: `data-testid` attributes (never CSS classes)
- Auth: use `storageState` for pre-authenticated sessions
- Run headless in CI, headed locally for debugging

## Backend Testing (xUnit)

### Unit Tests
- Location: `services/{Domain}/{Service}.Test/`
- One test class per service/handler class
- Use `Moq` for interface mocking (but never mock the database in integration tests)
- Arrange/Act/Assert pattern

### Integration Tests
- Location: `services/{Domain}/{Service}.IntegrationTests/`
- Hit a real database — never mock DB (past incident: mock/prod divergence)
- Use `WebApplicationFactory<T>` for API tests
- Test the full request pipeline

## Bug Reporting Template

```markdown
## Bug: [Brief description]

**Steps to reproduce:**
1. Navigate to [page]
2. Click [element]
3. Enter [data]

**Expected:** [What should happen]
**Actual:** [What actually happens]

**Environment:**
- Browser: Chrome 120
- User role: Admin / Employee
- Test user: [username]

**Evidence:**
- Screenshot: [path or attached]
- Video: [path or attached]
- Console errors: [if any]

**Severity:** Critical / High / Medium / Low
```

## Recommended External Skills

Install for enhanced testing capabilities:
```bash
# QA Skills — 20+ testing skills (Playwright, Jest, security, accessibility)
npx @qaskills/cli add playwright-e2e
npx @qaskills/cli add jest-unit-testing

# Agentic QE — AI-powered test generation and coverage analysis
npm install -g agentic-qe && cd your-project && aqe init --auto

# Playwright QA — No-code recording → production-ready tests
git clone https://github.com/sharmasundip/playwright-qa-skills.git ~/.claude/skills/playwright-qa
```
