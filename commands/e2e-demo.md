# /e2e-demo — Run E2E tests sequentially in headed browser (demo mode)

Runs Playwright tests across worktrees one at a time in a real browser window. Next worktree starts only when the previous finishes. Prints a pass/fail summary at the end.

## Usage

```
/e2e-demo [PROJ-1234 PROJ-5678 ...]
```

- No args — auto-detects all git worktrees
- With ticket IDs — runs those worktrees in order

## What to do

```bash
bash ~/.claude/scripts/e2e-queue.sh --headed [TICKET_IDS...]
```

If no ticket IDs were given, omit them (auto-detect kicks in).

## Examples

```
/e2e-demo                                         → all worktrees, sequential
/e2e-demo PROJ-2239 PROJ-2240 PROJ-2241           → three specific worktrees
```
