---
name: design-an-interface
description: Generate multiple radically different interface designs for a module using parallel sub-agents. Use when designing an API, service contract, hook, or component interface — or when someone mentions "design it twice".
autoTrigger:
  - when user wants to design a new API, service, hook, or component interface
  - when user mentions "design it twice" or wants to explore interface options
globs:
  - "**/*"
---

# Design an Interface

Based on "Design It Twice" from "A Philosophy of Software Design": your first idea is unlikely to be the best. Generate multiple radically different designs in parallel, then compare.

## What the User Provides

$ARGUMENTS

If no context is provided, ask: "What does this module need to do, and who will call it?"

## Workflow

### Step 1 — Gather requirements

Before designing, understand:

- What problem does this module solve?
- Who are the callers? (other services, frontend, tests)
- What are the key operations?
- Any constraints? (performance, existing patterns, backwards compatibility)
- What should be hidden inside vs exposed to callers?

Also explore the codebase briefly to understand:
- Existing patterns for similar modules
- Conventions in `docs/CODING_STYLE_BACKEND.md` or `docs/CODING_STYLE_FRONTEND.md`
- Adjacent interfaces the new module will interact with

### Step 2 — Generate designs (parallel sub-agents)

Spawn 3 sub-agents simultaneously using the Task tool. Each must produce a **radically different** approach. Assign a different constraint to each:

```
Prompt for each sub-agent:

Design an interface for: [module description]

Requirements: [gathered requirements]
Existing patterns to consider: [from codebase exploration]

Your constraint: [one of the below]
  Agent 1: "Minimize surface area — aim for 1-3 methods/props max"
  Agent 2: "Maximize flexibility — support all foreseeable use cases"
  Agent 3: "Optimize for the most common case — make the happy path effortless"

Stack context:
  - Backend (.NET): use C# interface syntax with Task<T> return types,
    ApiResponse<T> wrapper, and dependency injection patterns
  - Frontend (React/TS): use TypeScript types, hook signatures, or component
    props interfaces — follow named exports and CVA patterns

Output:
  1. Interface signature (types/methods/props)
  2. Usage example (how the caller uses it)
  3. What this design hides internally
  4. Trade-offs of this approach
```

### Step 3 — Present designs

Show each design clearly with:

1. **Interface signature** — types, methods, parameters
2. **Usage example** — how callers actually use it in practice
3. **What it hides** — complexity kept internal
4. **Trade-offs** — what you give up with this approach

Present designs one at a time so the user can absorb each before seeing the comparison.

### Step 4 — Compare designs

After showing all designs, compare on:

- **Interface simplicity**: fewer methods/props, simpler params = easier to use correctly
- **Depth**: small interface hiding significant complexity (good) vs large interface with thin implementation (bad)
- **General-purpose vs specialized**: flexibility vs focus — don't over-generalize
- **Implementation efficiency**: does the shape allow efficient internals, or force awkward workarounds?
- **Ease of correct use** vs **ease of misuse**
- **Fit with Repo conventions**: does it follow the layered architecture and naming patterns?

Discuss trade-offs in prose. Highlight where designs diverge most.

### Step 5 — Synthesize

The best design often combines insights from multiple options. Ask:

- "Which design best fits your primary use case?"
- "Any elements from other designs worth incorporating?"

If the user wants to proceed, offer to:
1. Write the final interface as a stub (no implementation)
2. Hand off to `/tdd` to implement with tests first
3. Create a Jira ticket with the design decision documented

## Evaluation Criteria

**Deep module** (aim for this): small, simple interface hiding significant complexity internally.

**Shallow module** (avoid): large, complex interface with thin or trivial implementation.

**Red flags in a design:**
- More methods than there are use cases
- Callers need to know internal state to call correctly
- The interface mirrors the implementation 1:1

## Anti-Patterns

- Don't let sub-agents produce similar designs — enforce the constraints strictly
- Don't skip the comparison step — the value is in the contrast
- Don't implement yet — this skill is purely about interface shape
- Don't pick a winner before the user has seen all options
