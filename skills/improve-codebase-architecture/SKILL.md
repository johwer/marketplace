---
name: improve-codebase-architecture
description: Audit a service or module for agent-friendliness — identify confusing boundaries, tightly coupled code, and shallow modules that make AI implementation harder and less reliable
autoTrigger:
  - when user says "improve architecture" or "refactor for agents"
  - when user asks to audit a service for testability or maintainability
globs:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.cs"
---

# Improve Codebase Architecture

## Purpose

Refactor codebases for clarity and testability — especially to make them more reliable for AI-assisted implementation. Tightly coupled, shallow, or confusingly-bounded modules produce inconsistent agent outputs. This audit identifies and fixes those.

## What the User Provides

$ARGUMENTS

If a specific service or directory is provided, audit that. Otherwise ask: "Which service or area do you want to audit?"

## Scope

Works on both:
- **Frontend** — React components, hooks, utilities in `apps/web/src/`
- **Backend** — .NET services in `services/<Service>/`

## Audit Workflow

### Step 1 — Map the module boundaries

Read the directory structure and key files to understand what exists:

```bash
# Frontend
find apps/web/src/<area> -type f | head -60

# Backend
find services/<Service>/<Service>/ -type f -name "*.cs" | head -60
```

For each module/file, note:
- What is its single responsibility? (if you can't state it in one sentence, that's a smell)
- What does it depend on?
- What depends on it?
- How testable is it in isolation?

### Step 2 — Identify the four problem patterns

#### 2a. Confusing module boundaries
Symptoms:
- File/class does two distinct things that could be split
- Name doesn't match what the code actually does
- Imports suggest a module knows too much about its siblings

Fixes:
- Split by responsibility, not by technical layer
- Rename to match actual behavior
- Move shared logic to a clearly named utility

#### 2b. Shallow modules
Symptoms (from John Ousterhout's *A Philosophy of Software Design*):
- Simple pass-through functions that add no abstraction value
- Interfaces that are as complex as their implementations
- One-liner wrappers that exist only to satisfy a pattern

Fixes:
- Merge shallow modules into their callers, or deepen them with real logic
- Replace trivial wrappers with direct calls
- Push complexity down — modules should hide difficult decisions, not expose them

#### 2c. Tightly coupled systems
Symptoms:
- Can't test a class without spinning up 5 dependencies
- Changes to one file require touching 6 others
- Business logic mixed into controllers, components, or data access layers

**Frontend fixes:**
- Extract business logic from components into custom hooks
- Extract pure transformations into utility functions (easily unit-tested)
- Use dependency injection via props or context instead of direct imports

**Backend fixes:**
- Enforce Controller → Service → Repository (never skip layers, never go backwards)
- Services receive interfaces, not concrete implementations
- No business logic in controllers or repositories

#### 2d. Poor pure function extraction
Symptoms:
- Logic that has no side effects but lives inside a class/component
- Functions that take state but don't modify it — could be pure
- Transformation logic entangled with I/O

Fixes:
- Extract pure functions to separate utility files
- Pure functions are trivially testable — this increases overall test coverage easily
- Name them after what they compute, not where they came from

### Step 3 — Prioritize findings

Score each finding:

| Priority | Criteria |
|----------|----------|
| **P1** | Blocks testability — can't write a unit test without this fix |
| **P2** | Makes agent implementation unreliable — AI makes wrong assumptions from confusing names/boundaries |
| **P3** | Reduces readability — humans struggle, but not a blocker |
| **P4** | Style/preference — worth fixing during normal feature work |

Only recommend implementing P1 and P2 findings immediately. P3/P4 go into tech debt backlog.

### Step 4 — Generate refactor plan

For each P1/P2 finding, produce a concrete refactor:

```
FINDING: [name]
Location: [file:line]
Problem: [one sentence]
Fix: [what to do]
Impact: [what becomes easier after this fix]
Risk: [what could break — migration path if needed]
Test: [how to verify the fix didn't change behavior]
```

### Step 5 — Plan before implementing (if multiple P1/P2 findings)

If there are 3 or more P1/P2 findings, suggest running `/request-refactor-plan` before touching any code:

> "There are [N] high-priority findings. Want me to run `/request-refactor-plan` first? It turns this into a structured tiny-commit plan filed as a Jira ticket — safer to implement incrementally than all at once. Or say 'just do it' to start implementing now."

If the user confirms, hand off to `/request-refactor-plan` with the audit findings as context.

### Step 6 — Implement (if user approves)

For approved refactors:

1. Write a characterization test first (captures current behavior)
2. Apply the refactor
3. Verify the characterization test still passes
4. Delete the characterization test if it's now covered by a better-structured test
5. Update any imports or references broken by the rename/move

### Step 6 — Verify

```bash
# Frontend
cd apps/web && npm run type-check && npm run test

# Backend
cd services/<Service>/<Service>.Test && dotnet test
```

No new test failures. No new type errors.

## Agent-Friendliness Checklist

After the audit, score the module against this checklist. Low scores = high refactor priority.

- [ ] Every file/class has a name that accurately describes what it does
- [ ] Every function/method can be described in one sentence
- [ ] Business logic lives in services/hooks, not controllers/components
- [ ] Pure functions are extracted and co-located with their domain
- [ ] No file depends on more than 5 other files directly
- [ ] Adding a new feature requires touching ≤ 3 files
- [ ] Every service/hook can be unit tested without a running database or browser

## Repo-Specific Patterns

**Frontend smells:**
- Business logic in `*.tsx` files (should be in `hooks/`)
- RTK Query cache mutations inline in components (should be in slice or hook)
- Repeated `useSelector` patterns that could be a custom hook

**Backend smells:**
- `Controller` calling `Repository` directly (skipping service layer)
- `Service` importing concrete `Repository` instead of `IRepository`
- Logic in `DbContext` `OnModelCreating` that belongs in a service
- Static helper methods on domain entities (extract to a service or utility)
