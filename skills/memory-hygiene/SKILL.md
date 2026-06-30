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

**Action:** Run the Archive Step below.

---

## Archive Step (dream-team-learnings.md)

Rolls processed session entries out of the active learnings file into a dated archive, so the file `/retro-proposals` loads on demand stays small. Suggest this whenever section 3's threshold trips; only run it after the user says yes.

### Iron rule — learnings have ONE home, and it is NEVER the recall system

This step moves entries **only between `dream-team-learnings.md` and `dream-team-learnings-archive-YYYY-MM.md`**. It must **NEVER**:
- write a learning into `MEMORY.md`
- create or append to any `feedback_*` / `reference_*` / `project_*` recall file
- add a `MEMORY.md` index line for the archive

Learnings are captured in `dream-team-learnings.md` and routed to their ONE canonical home (skill/doc/code/CLAUDE.md) by `/retro-proposals` — see `retro-proposals.md` ("ONE canonical home — never route to memory AND elsewhere"). Memory recall is a *fallback for learnings with no other home*, never a mirror of the learnings log. Archiving is pure log rotation; it does not touch the recall system at all.

### Procedure

1. **Process first — never archive unprocessed learnings.** Confirm `/retro-proposals` has already routed the entries you're about to move. If there are unrouted learnings, run `/retro-proposals` and stop here — come back to archive afterward.

2. **Keep the tail hot.** Leave the most recent **2–3 sessions** in the active `dream-team-learnings.md`. Everything older is an archive candidate. Session blocks start with `## Session: YYYY-MM-DD — <TICKET>`.

3. **Append older blocks to a dated archive**, grouped by the month the session occurred (`dream-team-learnings-archive-YYYY-MM.md` in the same memory directory). Append — never overwrite an existing archive. Create the archive file with a `# Dream Team Learnings — Archive YYYY-MM` heading if it doesn't exist.

4. **Remove the moved blocks from the active file.** After the move, the active file holds only its `# Dream Team Learnings` heading plus the last 2–3 session blocks.

5. **Verify the rotation (and the iron rule):**
   ```bash
   MEM=~/.claude/projects/*/memory
   wc -l $MEM/dream-team-learnings.md $MEM/dream-team-learnings-archive-*.md
   # MEMORY.md must be UNCHANGED — archive never adds an index line:
   grep -c "dream-team-learnings-archive" $MEM/MEMORY.md   # expect 0
   ```
   Confirm: active file shrank, archive grew by the same content, `MEMORY.md` untouched, no new recall files created.

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

Present findings as a short report. **Always fill these in with real measurements** (from the bash checks above) — the layout below is an illustrative template, NOT reference values. Placeholders are shown in `<…>`; replace every one.

```
🧹 Memory Health Check

  MEMORY.md:           <N> lines / <N> tokens (budget: 1,500) <✅ ok | ⚠️ over>
  Memory files:        <N> files / <N> tokens total
  dream-team-learnings: <N> lines <— consider archiving if over 500>

  Suggestions:
  1. [action] — [why] — saves ~<N> tokens
  2. [action] — [why] — saves ~<N> tokens

  Apply suggestions? (y/N)
```

> The `<…>` are placeholders, not data. Never echo them — or any number from this template — as if they were the user's actual figures. Measure first, then report.

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
