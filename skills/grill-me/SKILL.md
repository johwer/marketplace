---
name: grill-me
description: Design exploration through relentless interviewing — flesh out ideas before writing a single line of code or ticket
autoTrigger:
  - when user says "grill me" or "grill me on"
  - when user wants to explore a design idea before creating a ticket
  - when user says "I'm thinking about" and it sounds like a new feature or architecture change
globs:
  - "**/*"
---

# Grill Me — Design Exploration Interview

## Purpose

Forces thorough design conversation before premature planning or implementation. Based on Frederick P. Brooks' "design tree" concept: walk down each branch, resolve dependencies between decisions one by one.

Do NOT jump to conclusions, suggest implementations, or generate plans until the interview is complete and a shared understanding is reached.

## What the User Provides

$ARGUMENTS

If arguments are provided, treat them as the idea to explore. Otherwise ask: "What idea do you want to explore?"

## Interview Protocol

### Phase 1 — Frame the problem

Start by understanding what problem this is solving, not what the solution looks like:

- What is the actual user pain point or business need?
- Who specifically has this problem? (role, frequency, severity)
- What does success look like? How will we know it's solved?
- Why hasn't this been solved already? What's blocked it?

### Phase 2 — Walk the design tree

For each major design decision, explore both branches before moving on. Resolve upstream decisions before downstream ones (e.g., decide the data model before the API contract, decide the API before the UI).

Typical branches to explore:
- **Scope** — What's in? What's explicitly out? What's deferred?
- **Data model** — What entities are affected? New tables, columns, or relationships?
- **API contract** — New endpoints? Changes to existing ones? Breaking changes?
- **Frontend** — New pages, components, flows? Affected existing views?
- **Permissions** — Which roles can see/do what? Any new permission types?
- **Edge cases** — What are the failure modes? Null/empty states? Concurrent access?
- **Migration** — Existing data? Backwards compatibility? Feature flags needed?
- **Dependencies** — Which services are affected? Any cross-service event flows?

### Phase 3 — Challenge assumptions

After the initial exploration, explicitly challenge the hidden assumptions:

- "You said X — is that always true, or only when Y?"
- "What if [edge case]? Does the design hold?"
- "Is there an existing pattern we should reuse or extend?"
- "Have we considered [alternative approach]? Why is this approach better?"

### Phase 4 — Confirm shared understanding

Summarize the decisions reached and any open questions that remain. Ask the user to confirm:

- Decision log: what was decided and why
- Open questions: what still needs to be resolved (by whom, by when?)
- Risks: what could go wrong in implementation
- Recommendation: is this ready to write a ticket for, or does it need more exploration?

## Style

- Ask multiple questions at once (grouped by theme) — don't drip one question per turn
- Be relentless but constructive — the goal is clarity, not gotchas
- If an answer reveals a dependency, pursue that branch before moving on
- Typical session generates 16–50+ questions across all phases

## After the Interview

When shared understanding is reached, offer:

1. **Draft ticket** — Write a Jira-ready ticket with description, ACs, and open questions
2. **PRD** — Write a structured Product Requirements Document
3. **Architecture plan** — Write an implementation plan for `/my-dream-team`
4. **Nothing** — If the user just wanted to think out loud

Ask the user which output they want before generating anything.
