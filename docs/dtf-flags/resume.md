# DTF: --resume
Read when the arguments contain `--resume`. This runs instead of the normal Phase 1-7 workflow: it reconstructs context from persistent artifacts and continues the work.

1. **Determine ticket ID** from the arguments or current directory.

1.5. **AWS session check** — SSO tokens can expire between sessions:
   ```bash
   bash ~/.claude/scripts/aws-check.sh
   ```
   Credentials are **shared across worktrees** (on disk in `~/.aws`, not per-tmux) — if the parent or another worktree already logged in and the token is valid, you already have access; don't re-prompt. If it fails, prefer the SSO refresh (nothing secret to copy): suggest `! aws sso login --sso-session repo`, then use `AWS_PROFILE=repo-sso` for aws/S3 commands. Only fall back to paste-temp-creds (in the user's own terminal) if SSO login genuinely fails. Treat a mid-session expiry as "refresh and continue," not a hard human blocker.

1.7. **An orchestrator relay can arrive after its work is done.** Check state first (ancestry, PR
   base, body text), then do only the delta.

1.8. **Rebased onto a merged base that had migrations?** Compare `__EFMigrationsHistory` with the
   migrations in code before starting a service. Roll an orphaned one back per its own `Down()`,
   after a dump.

2. **Verify working directory** — confirm you are running from the worktree, not the main repo:
   ```bash
   pwd  # Should be ~/Documents/<TICKET_ID>, NOT ~/Documents/Repo
   ```
   If you're in the main repo, `cd` to the worktree: `cd ~/Documents/<TICKET_ID>` (or `$DTF_WORKTREE_PARENT/<TICKET_ID>`).

3. **Validate worktree environment** — check ports and env files before anything else:
   ```bash
   # Check .env exists with port allocations
   if [ ! -f .env ]; then
     echo "⚠️ .env missing — regenerating..."
     bash ~/.claude/scripts/allocate-ports.sh <TICKET_ID>
   fi
   grep -E "^(ServiceB|ServiceC|ABSENCE|STATISTICS|MESSENGER)_API_PORT=" .env

   # Check Vite config
   cat apps/web/.env.local 2>/dev/null | grep VITE_DEV_PORT

   # Check for stale Docker containers on worktree ports
   for port in $(grep "_API_PORT=" .env 2>/dev/null | cut -d= -f2); do
     lsof -ti :$port 2>/dev/null && echo "⚠️ Port $port already in use"
   done
   ```
   If `.env` is missing or ports are stale, re-run `bash ~/.claude/scripts/allocate-ports.sh <TICKET_ID>`. Report any port conflicts to the user.

4. **Gather current state** — read all of these:
   ```bash
   # What code changes exist
   git diff --name-only
   git log --oneline -10
   git status --short

   # Diff each commit SEPARATELY — never judge the branch in aggregate.
   for c in $(git log --format=%H origin/main..HEAD); do
     echo "=== $c: $(git log -1 --format=%s $c)"
     git show --stat $c
   done

   # PR status (if exists)
   cd ~/Documents/Repo && gh pr list --head <TICKET_ID> --state all --json number,title,state,url,body

   # Agent notes from previous session
   ls .dream-team/notes/ 2>/dev/null
   cat .dream-team/notes/*.md 2>/dev/null

   # Agent journals from previous session
   cat .dream-team/journal/*.md 2>/dev/null

   # Jira ticket status
   acli jira workitem view <TICKET_ID>

   # Check if Docker services are still running from previous session
   docker ps --format '{{.Names}}' | grep -i "<TICKET_ID>" 2>/dev/null
   ```

4.5. **Compile what the previous session pushed — BEFORE any planning.**

   ```bash
   bash ~/.claude/scripts/quality-gate.sh "$(pwd)"
   ```

   A resumed branch may never have compiled; build before planning.

   Report the result as one of three states, and do not merge them:
   - **green** — proceed.
   - **red** — the previous session pushed a regression. That is now the first work item, ahead of
     whatever the ticket says.
   - **unverified** — the toolchain could not run (SDK pin mismatch, missing container runtime).
     This is NOT a pass. Say "backend unverified" explicitly; `quality-gate.sh` reports it through
     the same ".NET build failed" path as a real regression, which reads as an environment nit.

4.6. **Spot-check the evidence the notes claim, not just the build.** A green gate proves the branch
   compiles; it does not prove the previous session's screenshots or measurements show what the
   notes say. Open each `~/Downloads/<TICKET_ID>/` capture the notes call verified and confirm it
   shows the claimed role, state and data. Then run `bash ~/.claude/scripts/dtf-preflight.sh <worktree>` (Phase 1 step 1b).

5. **Assess what phase the previous session was in** based on the gathered context:
   - **No code changes, no PR** → Previous session barely started. Start fresh from Phase 1.
   - **Code changes exist, no PR** → Implementation was in progress. Skip to Phase 2 with context.
   - **Draft PR exists, code pushed** → Implementation is done or nearly done. Check if review/testing is needed.
   - **PR is ready (not draft)** → Review cycle. Check for feedback to address.
   - **Status file says "done"** → Previous session completed. Ask user what needs to happen next (fixes? additional work?).

6. **Present a summary to the user**:
   ```
   ## Resume: <TICKET_ID>
   - **Working directory:** [confirmed worktree path]
   - **Environment:** [.env OK / .env regenerated / ⚠️ port conflicts]
   - **Docker services:** [running: X, Y / none running]
   - **Previous state:** [what phase it was in]
   - **Code changes:** [X files modified]
   - **PR:** [draft/ready/none] — [URL if exists]
   - **Agent notes found:** [list of agents who left notes]
   - **What I'll do next:** [proposed action]
   ```
   Ask the user to confirm before proceeding.

7. **Create a fresh team** (`dream-team-<TICKET_ID>`) and spawn agents as needed for the remaining work. Include in each agent's prompt:
   - "You are resuming work from a previous session"
   - "Your working directory is `<worktree-path>` — verify all file operations use this path"
   - "Read your notes file at `.dream-team/notes/<your-name>.md` for decisions and progress from last session"
   - What's already been done (from git diff and agent notes)
   - What remains to be done
   - The worktree ports from `.env` (so agents don't need to re-discover them)

8. **Continue from the appropriate phase** in the normal workflow.

- Phase 4 Step 0 (`/reviewing-changes`): skip this step on such a branch and say so in the PR body and to the user.
