---
name: memory-hygiene
description: Review and clean up memory files to keep context costs low — triggered during cleanup, compact, or session end
---

## When to Trigger

Memory cleanup belongs at **session start** — before work begins, when the context is clean and nothing is in-flight. Never during active work or compaction (you might delete something that's still needed).

**Good triggers (session start):**
- `/create-stories` Step 0 (cleanup phase, before any tickets)
- `/workspace-launch` Step 0 (before fetching ticket)
- `/infra-ticket` Step 0 (before fetching ticket)
- When the user explicitly says "clean up", "housekeeping", or "check memory"

**Bad triggers (never here):**
- During `/compact` — context is under pressure, memories may still be relevant
- Mid-implementation — you might delete something you need
- During code review — you need the full context

The bash script runs first (0 tokens). Only invoke the skill if warnings are found AND the user says yes.

## What to Check

### 1. MEMORY.md Index Size

```bash
wc -l ~/.claude/projects/*/memory/MEMORY.md
```

**Threshold:** > 150 lines is getting close to the 200-line truncation limit.

**Action:** Suggest consolidating or removing entries that:
- Point to memory files that no longer exist
- Are duplicates (two entries pointing to same concept)
- Are about code patterns that are now in AGENTS.md or conventions docs (redundant)

### 2. Stale Memory Files

For each memory file in the memory directory:

```bash
ls -la ~/.claude/projects/*/memory/*.md
```

Check each file against current reality:
- **Project memories** — Is this project/initiative still active? Has the deadline passed?
- **Feedback memories** — Is the feedback still relevant? Has the convention been formalized into a doc?
- **Reference memories** — Does the external resource still exist? Has the URL changed?
- **User memories** — Still accurate about the user's role/preferences?

**Stale indicators:**
- References a file that no longer exists → verify with `ls`
- References a function/feature that was renamed/removed → verify with `grep`
- Contains a date in the past for a deadline/freeze → probably stale
- Duplicates what's now in CLAUDE.md or a conventions doc → redundant

### 3. dream-team-learnings.md Size

This file grows with every Dream Team session. It's not loaded automatically, but it gets referenced by `/retro-proposals`.

```bash
wc -l ~/.claude/projects/*/memory/dream-team-learnings.md
```

**Threshold:** > 500 lines

**Action:** Suggest running `/retro-proposals` to process learnings into destination files, then archive old entries:
1. Run `/retro-proposals` to route unprocessed learnings
2. Move processed entries to `dream-team-learnings-archive-YYYY-MM.md`
3. Keep only the last 2-3 sessions in the active file

### 4. Token Budget Check

Calculate total cost of always-loaded memory:

```bash
# MEMORY.md tokens (loaded every prompt)
wc -w ~/.claude/projects/*/memory/MEMORY.md | awk '{printf "MEMORY.md: %d tokens\n", $1 * 1.3}'
```

**Budget guideline:**
| Component | Budget | Why |
|-----------|--------|-----|
| MEMORY.md | < 1,500 tokens | Loaded every single prompt |
| Individual memories | < 500 tokens each | Loaded on access |
| Total memory dir | < 15,000 tokens | Full read during cleanup |

If MEMORY.md exceeds 1,500 tokens, suggest:
- Moving detailed content from MEMORY.md into individual memory files (MEMORY.md should be an index with links, not content)
- Archiving project memories for completed work
- Promoting stable feedback to CLAUDE.md or conventions docs (then removing the memory)

## Output Format

Present findings as a short report:

```
🧹 Memory Health Check

  MEMORY.md:           136 lines / 1,827 tokens (budget: 1,500) ⚠️ slightly over
  Memory files:        10 files / 14,473 tokens total
  dream-team-learnings: 615 lines — consider archiving processed entries

  Suggestions:
  1. [action] — [why] — saves ~X tokens
  2. [action] — [why] — saves ~X tokens

  Apply suggestions? (y/N)
```

## What NOT to Do

- Don't delete memories without asking
- Don't archive learnings without running `/retro-proposals` first
- Don't touch memories during active implementation work — only at maintenance moments
- Don't nag — suggest once, respect the answer
- Don't move content to CLAUDE.md without checking if it's already there (duplicates are worse than stale memory)

## Promotion Path

When a memory has been confirmed multiple times and is stable:

```
Memory file (cross-session learning)
  ↓ confirmed 3+ times, stable pattern
Conventions doc or CLAUDE.md (permanent, loaded automatically)
  ↓ memory file deleted (no longer needed)
Tokens saved: ~200-500 per prompt
```

This is the natural lifecycle: learn → remember → formalize → forget.
