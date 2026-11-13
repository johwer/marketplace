---
name: strategic-compact
description: Proactive context management — suggests /compact at logical breakpoints to maintain quality in long sessions. Use when a long session reaches a phase boundary (research done, milestone reached, debugging finished) or switches between major phases of work.
---

# Strategic Compaction

## Purpose

Long sessions degrade output quality as context fills up. This skill provides rules for WHEN to compact — at phase boundaries, not mid-work.

## When to Compact

### GOOD breakpoints (suggest /compact here):
1. **After research/exploration completes** — You've read files, grepped code, understand the problem. Compact before writing code.
2. **After a milestone** — Feature implemented, tests passing, PR created. Compact before the next phase.
3. **After a debugging session** — Bug found and fixed. The investigation context is no longer needed.
4. **After agent results are absorbed** — Subagent returned findings, you've noted the key points. The raw exploration data can be compressed.
5. **Phase transitions in Dream Team** — Between Phase 1→2, 3→4, 4→5. Each phase has distinct context needs.

### BAD times to compact (NEVER compact here):
1. **Mid-implementation** — You're editing files, running tests, iterating. Compacting loses the "what I just tried" context.
2. **During code review** — You need the full diff context to give coherent feedback.
3. **While debugging** — You need the error context, stack traces, and hypotheses.
4. **Between related file edits** — If you're editing 3 files that depend on each other, finish all 3 first.

## Context Usage Awareness

Auto-compaction fires at 50% (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`), so the goal is to reach a good breakpoint before it does: in a long session, suggest /compact at the next breakpoint above rather than letting auto-compaction land mid-work.

## How to Compact Well

Before suggesting /compact:
1. **Summarize key decisions** in your response — these survive compaction
2. **Note any file paths** you'll need to revisit
3. **State what phase you're in** and what comes next
4. The PreCompact hook will automatically save a CHECKPOINT.md file


## Dream Team Integration

For Dream Team sessions, the team lead should compact:
- After Phase 1 (architecture) → before spawning dev agents
- After Phase 3 (coordination) → before spawning Maya
- After Phase 4 (review) → before Phase 5 (commit/push)
- After Phase 5.5 (CI/review cycle) → before Phase 6 (user feedback)

Subagents have their own context windows and don't need the lead's compaction schedule.
