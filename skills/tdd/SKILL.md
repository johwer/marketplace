---
name: tdd
description: Test-driven development loop — red-green-refactor with interface confirmation before writing any implementation
autoTrigger:
  - when user says "tdd" or "test-driven"
  - when implementing a new service method, hook, or utility that has clear input/output contracts
globs:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.cs"
---

# TDD — Test-Driven Development Loop

## Purpose

Forces the red-green-refactor discipline. The most consistent way to improve agent output quality: write the test first, let it fail, then write the minimum code to pass it, then refactor.

Never write implementation before at least one failing test exists.

## What the User Provides

$ARGUMENTS

If arguments are provided, treat them as the feature or function to implement. Otherwise ask what to build.

## Stack Detection

Detect the stack from file context or arguments:

- **Frontend** (`.ts`, `.tsx` in `apps/web/`): Vitest + React Testing Library
- **Backend** (`.cs` in `services/`): xUnit + NSubstitute + FluentAssertions

## Workflow

### Step 1 — Confirm the interface

Before writing any tests, confirm the contract:

- What is the function/method/component name?
- What are the inputs? (types, shapes, constraints)
- What are the outputs? (return type, side effects, events emitted)
- What are the failure modes? (errors thrown, validation failures, edge cases)

Write out the interface as a type signature or method stub (no implementation yet). Ask the user to confirm it before proceeding.

**Frontend example:**
```ts
// Interface to confirm:
function calculateServiceADays(
  startDate: Date,
  endDate: Date,
  excludeWeekends: boolean
): number
```

**Backend example:**
```csharp
// Interface to confirm:
Task<ApiResponse<ServiceASummary>> GetServiceASummaryAsync(
    int employeeId,
    DateOnly from,
    DateOnly to,
    CancellationToken ct = default);
```

### Step 2 — Design the test cases

Before writing any test code, list the cases to cover:

| # | Scenario | Input | Expected output |
|---|----------|-------|-----------------|
| 1 | Happy path | ... | ... |
| 2 | Empty/null input | ... | error or default |
| 3 | Edge case | ... | ... |
| 4 | Error/failure case | ... | ... |

Confirm with user before writing. Add or remove cases based on their feedback.

### Step 3 — Red: write ONE failing test

Write the first test only. Run it. Verify it fails with a meaningful error (not a compilation error — that means the interface isn't set up yet).

**Frontend:**
```bash
cd apps/web && npx vitest run --reporter=verbose <test-file-path>
```

**Backend:**
```bash
cd services/<Service>/<Service>.Test && dotnet test --filter "<TestName>"
```

The test must fail for the right reason — not "file not found" or "method doesn't exist", but an assertion failure.

### Step 4 — Green: write minimum implementation

Write the smallest possible implementation that makes the failing test pass. Do not add logic for cases not yet tested. Resist the urge to handle all edge cases up front.

Run the test again. It must pass before moving on.

### Step 5 — Refactor

With the test green, improve the implementation without changing behavior:

- Extract duplicated logic
- Rename for clarity
- Apply project conventions (see frontend/backend conventions skills)
- Ensure types are correct and explicit

Run tests again after refactoring. Still green? Move on.

### Step 6 — Repeat for next case

Return to Step 3 with the next test case from the list. Continue until all cases are covered.

### Step 7 — Final check

Run the full test file (not just the new tests) to catch regressions:

**Frontend:**
```bash
cd apps/web && npx vitest run --reporter=verbose <test-file-path>
```

**Backend:**
```bash
cd services/<Service>/<Service>.Test && dotnet test
```

Also run type-check for frontend:
```bash
cd apps/web && npm run type-check
```

## Test File Conventions

### Frontend (Vitest)

```ts
import { describe, expect, it } from "vitest"
// REQUIRED — CI tsc --noEmit fails without this (TS2593/TS2304)

describe("functionName", () => {
  it("should <expected behavior>", () => {
    // arrange
    // act
    // assert
  })
})
```

File location: co-located with the source file as `<filename>.test.ts`.

### Backend (xUnit)

```csharp
public class ServiceNameTests
{
    private readonly IServiceNameRepository _repository = Substitute.For<IServiceNameRepository>();
    private readonly ServiceName _sut;

    public ServiceNameTests()
    {
        _sut = new ServiceName(_repository);
    }

    [Fact]
    public async Task MethodName_WhenCondition_ShouldExpectedBehavior()
    {
        // Arrange
        // Act
        var result = await _sut.MethodNameAsync(...);
        // Assert
        result.Should().Be(...);
    }
}
```

## What NOT to Do

- Don't write all tests first, then all implementation — one test at a time
- Don't write implementation "to get ahead" before a test fails
- Don't skip the refactor step — accumulating unrefactored green tests is tech debt
- Don't mock things that can be pure functions — test the real logic
