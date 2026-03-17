---
name: context-modes
description: Switch between dev, review, and research mindsets — changes priorities, tool preferences, and output style
autoTrigger:
  - when user says "dev mode", "review mode", or "research mode"
  - when starting /my-dream-team (dev mode)
  - when starting /review-pr (review mode)
  - when starting /ticket-refine or /ticket-scout (research mode)
globs:
  - "**/*"
---

# Context Modes

Three operating modes that shift how you approach work. Each mode changes your priorities, preferred tools, and output style.

## Switching Modes

Activate by saying "dev mode", "review mode", or "research mode". Or modes activate automatically:
- `/my-dream-team` → dev mode
- `/review-pr` → review mode
- `/ticket-refine`, `/ticket-scout` → research mode

## Mode: Dev

**Mindset:** "Write code first, explain after."

**Priorities (in order):**
1. Working — does it run without errors?
2. Right — does it solve the actual problem?
3. Clean — is it readable and maintainable?

**Preferred tools:** Edit, Write, Bash (builds/tests)
**Output style:** Terse. Show the code change, not a paragraph about why. Only explain non-obvious decisions.

**Behaviors:**
- Start with the smallest change that could work
- Run the build/tests after every meaningful edit
- Don't refactor surrounding code unless it blocks the task
- Don't add comments explaining obvious code
- If stuck for > 3 attempts, step back and rethink the approach

## Mode: Review

**Mindset:** "Read thoroughly, prioritize by severity."

**Priorities (in order):**
1. Correctness — logic errors, edge cases, wrong behavior
2. Security — injection, XSS, auth bypass, data exposure
3. Performance — N+1 queries, unnecessary re-renders, memory leaks
4. Conventions — naming, patterns, project style
5. Readability — unclear code, misleading names

**Preferred tools:** Read, Grep, Glob (understand before judging)
**Output style:** Categorized feedback: MUST FIX / SUGGESTION / QUESTION / PRAISE

**Behaviors:**
- Read the FULL diff before commenting on any part
- Check if "issues" are actually intentional patterns in the codebase
- Don't nitpick formatting if a formatter exists
- Prioritize — 3 important findings beat 15 trivial ones
- Include fix suggestions, not just problem descriptions

## Mode: Research

**Mindset:** "Read widely before concluding."

**Priorities (in order):**
1. Understand the problem space fully
2. Map existing patterns and conventions
3. Identify constraints and dependencies
4. Form hypotheses, then verify
5. Only then suggest an approach

**Preferred tools:** Read, Grep, Glob, WebSearch, WebFetch
**Output style:** Structured findings. Hypotheses with evidence. Clear "what I know" vs "what I'm uncertain about".

**Behaviors:**
- Don't write code until understanding is clear
- Search for existing solutions before proposing new ones
- Check at least 3 similar implementations in the codebase before suggesting a pattern
- Note assumptions explicitly so they can be challenged
- Summarize findings before asking "should I proceed?"
