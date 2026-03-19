# /e2e-show — Show Playwright E2E tests in browser, skip failing ones

Run passing E2E tests in headed or UI mode. Probes headlessly first to find which tests currently fail, then skips them so you only see green tests. Vite proxy noise (ECONNREFUSED) is filtered from output automatically.

## Usage

```
/e2e-show [--ui] [--refresh]
/e2e-show --all [PROJ-1234 PROJ-5678 ...] [--ui]
```

**Single worktree** (current directory):
- (no flag) — headed mode, browser pops up, tests run automatically
- `--ui` — Playwright interactive UI, pick/filter tests yourself
- `--refresh` — ignore cached probe results and re-probe

**Parallel worktrees** (`--all`):
- `--all` — open one terminal window per worktree, all run in parallel
- `--all PROJ-1234 PROJ-2229` — specific worktrees only
- `--all --ui` — open Playwright UI mode in each terminal

> For sequential demo runs across worktrees, use `/e2e-demo` instead.

## What to do

Parse the args from the command message.

**If `--all` is in the args:**
```bash
bash ~/.claude/scripts/e2e-show-all.sh [TICKET_IDS...] [--ui|--headed]
```

**Otherwise (single worktree):**
```bash
node ~/.claude/scripts/e2e-show.mjs [--headed|--ui] [--refresh]
```

Run from the current working directory — scripts locate `apps/web/` automatically.

## Examples

```
/e2e-show                           → headed, current worktree
/e2e-show --ui                      → Playwright UI, current worktree
/e2e-show --all                     → headed, all worktrees in parallel
/e2e-show --all PROJ-2238 PROJ-2229 → two specific worktrees, parallel
/e2e-show --all --ui                → UI mode in all worktrees
/e2e-show --refresh                 → re-probe before running
```

## Notes

- Cache lives at `apps/web/.playwright-show-cache.json` (local, not committed)
- Cache is valid for 5 minutes per worktree — each worktree has its own cache
- ECONNREFUSED proxy errors are filtered — they're harmless Vite noise when backend isn't running
- Worktrees are auto-detected via `git worktree list` from the main repo
- Each worktree uses its own port from `apps/web/.env.local`
