# DTF: --interview
Read when the arguments contain `--interview`.

- **Before any other phase**, interview the user about the ticket. In the Repo repo, do it by invoking **`/grill-me`** (`.claude/skills/grill-me/SKILL.md`, root `AGENTS.md` "Plan"); elsewhere, or on a branch without that skill, use the AskUserQuestion tool as below
- Ask about: technical constraints they know about, edge cases, UX expectations, things the ticket description doesn't cover, dependencies on other work, and what "done" looks like to them
- Don't ask obvious questions — dig into the hard parts they might not have considered
- Keep interviewing until you've covered everything (typically 3-6 questions)
- Write the findings to `.dream-team/interview.md` in the worktree
- Amara (or you in lite mode) reads this file in Phase 1 — the interview findings take priority over assumptions from the ticket text
- Can be combined with any other flag (`--lite --interview`, `--local --interview`)
