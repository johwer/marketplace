# Create Stories — Full Lifecycle Orchestrator

You are orchestrating the full development lifecycle for one or more Jira tickets: workspace setup, team handoff, and cleanup.

## Config Resolution

Read `~/.claude/dtf-config.json` if it exists. Use:
- `paths.monorepo` instead of `~/Documents/Repo`
- `paths.worktreeParent` instead of `~/Documents`
- `terminal` instead of the hardcoded terminal name
If no config exists, fall back to the values in `~/.claude/CLAUDE.md`.

## Input

The user provides one or more **ticket IDs** (e.g., `PROJ-1234` or `PROJ-1234 PROJ-1434`), space or comma separated.

$ARGUMENTS

## Trigger

This skill should be invoked when the user says things like:
- "Create stories for PROJ-1234 and PROJ-1434"
- "Set up these tickets: PROJ-1234, PROJ-1434"
- "Work on PROJ-1234 and PROJ-1434"
- "Launch these stories: ..."

## Flags

Check if the arguments contain any of these flags. Pass them through to `/my-dream-team` when launching.

- `--lite` — Pass to `/my-dream-team`. Claude decides whether to spawn agents. All other lifecycle steps (worktree, deps, PR, cleanup) still run normally.
- `--no-worktree` — Skip Steps 4-6 (worktree creation, npm install, env copy). Launch Claude in a new terminal but `cd` to the monorepo and work on the current branch. Cleanup skips worktree removal — only kills the tmux session.
- `--local` — Pass to `/my-dream-team`. No PR, no push.

Flags can be combined: `--lite --no-worktree`, `--lite --local`, etc.

## Workflow

The workflow has two phases: **parallel pre-hydration** (all tickets at once) and **sequential launch** (one at a time). This saves significant startup time — Amara doesn't need to re-explore files that were already analyzed.

---

### Step 0: Clean Up Stale Worktrees

Before creating new workspaces, check if any existing worktrees have merged/closed PRs that can be cleaned up. This prevents worktree buildup over time.

1. **List existing worktrees and check PR status:**
   ```bash
   cd ~/Documents/Repo && git worktree list
   ```
   For each worktree (excluding main), check its PR status:
   ```bash
   gh pr list --head <BRANCH> --state all --json number,state,mergedAt,title
   ```

2. **If any worktrees have MERGED or CLOSED PRs**, present them to the user:
   ```
   ## Stale Worktrees Found

   | Worktree | PR | Status |
   |----------|----|--------|
   | PROJ-1234 | #1700 | MERGED |
   | PROJ-1235 | #1701 | CLOSED |
   ```
   Ask the user with AskUserQuestion which ones to clean up. **Always ask** — some may need to be kept (e.g., reverted PRs with code that a new ticket references).

3. **For each confirmed cleanup**, run from the main repo (NOT from inside the worktree):
   ```bash
   cd ~/Documents/Repo && git worktree remove ~/Documents/<TICKET_ID> --force
   rm -rf ~/Documents/<TICKET_ID>
   git branch -D <TICKET_ID>
   git worktree prune
   rm -f ~/.claude/workspace-status/<TICKET_ID>.json
   ```

4. **If no stale worktrees**, skip silently and proceed.

5. **Also kill any orphan tmux sessions** that don't have a matching worktree:
   ```bash
   tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^PROJ-'
   ```
   For each session without a matching worktree, kill it:
   ```bash
   tmux kill-session -t <SESSION_NAME> 2>/dev/null || true
   ```

---

### Phase A: Parallel Pre-Hydration (All Tickets)

#### Step 1: Fetch ALL Tickets from Jira (Parallel)

Fetch all tickets in parallel using the Agent tool (one agent per ticket, subagent_type `Explore`, model `haiku`):

```
For each ticket ID, spawn an explore agent:
  "Fetch Jira ticket <TICKET_ID>: run `acli jira workitem view <TICKET_ID>` and return the full output including summary, description, acceptance criteria, and attachment URLs."
```

If any ACLI call fails, note it — you'll ask the user for those ticket details in Step 4.

#### Step 2: Handle Attachments

After all tickets are fetched, download attachments for any tickets that have them.

**Default method — API download (no Chrome needed):**
```bash
bash ~/.claude/scripts/jira-download-attachments.sh <TICKET_ID> [OUTPUT_DIR]
```

Downloads to `~/Downloads/<TICKET_ID>/` by default. Returns file paths on stdout, `NO_ATTACHMENTS` if none. Uses the ACLI OAuth token from macOS keychain to download via the public Atlassian API.

For each ticket with attachments:
1. Run the download script
2. Read the downloaded images/PDFs using the Read tool to understand context
3. Include findings in the pre-hydrated context file (Step 8)

**Fallback — Chrome (only if API download fails):**
If the script exits with code 2 (token or API failure), fall back to opening attachments in Chrome:
```bash
open -a "Google Chrome" "<ATTACHMENT_URL>"
```
Then ask the user to confirm once downloads are complete.

#### Step 3: Pre-Hydrate ALL Contexts (Parallel)

Spawn **parallel explore agents** (one per ticket, subagent_type `Explore`, model `sonnet`) to analyze each ticket against the codebase. Each agent receives the ticket info from Step 1 and runs a lightweight version of Amara's Phase 1 analysis:

```
For each ticket, spawn an explore agent with this prompt:

"You are pre-analyzing ticket <TICKET_ID> for the Repo monorepo at ~/Documents/Repo.

Ticket: <FULL_TICKET_TEXT_FROM_STEP_1>

Analyze the codebase to determine:
1. **Scope**: backend-only, frontend-only, or full-stack
2. **Complexity**: small (1-3 files), medium (4-8 files), large (8+ files)
3. **Key files**: List the main files that will need modification (verify paths exist with Glob)
4. **Affected services**: Which services/areas of the codebase are involved
5. **Dependencies**: Does this ticket depend on or conflict with common hot files (AppRoutes.tsx, EmployeeCardTabs.tsx)?
6. **Existing patterns**: Are there existing components/patterns that should be reused?
7. **Conventions summary**: Key conventions from docs/ that apply to this ticket's scope
8. **API contract** (if full-stack): Endpoint paths, methods, request/response shapes
9. **Seed data**: Does seed data exist in scripts/database-init/ for the entities involved?
10. **Needs testing**: Does this need functional testing? (yes for: API changes, migrations, complex UI interactions)
11. **Needs Docker rebuild**: Which service(s) need rebuilding?
12. **Recommended mode**: Based on complexity and scope, recommend: Dream Team (medium/large, multi-discipline), Lite (small/medium, single discipline), or Just worktree (trivial or blocked)
13. **Recommended team**: Which agents are needed and at what model tier

Return your analysis as a structured report."
```

#### Step 4: Present Recommendations Table

After all pre-hydration agents return, present a summary table to the user:

```
## Ticket Analysis

| Ticket | Summary | Scope | Complexity | Recommended | Key Files |
|--------|---------|-------|------------|-------------|-----------|
| PROJ-1234 | Add mobile number field | full-stack | medium | Dream Team | EmployeeContact.tsx, ServiceB/ContactController.cs |
| PROJ-1235 | Fix date picker styling | frontend-only | small | Lite | DatePicker.tsx |
| PROJ-1236 | Update seed data | backend-only | small | Just worktree | database-init/seed.sql |
```

For any tickets where ACLI failed in Step 1, note "Ticket fetch failed — need details from you" in the table.

#### Step 5: User Confirms Per Ticket

Ask the user to confirm the launch mode for each ticket using AskUserQuestion. Present one question per ticket (up to 4 at a time):

- **"How should we work on \<TICKET_ID\> (\<SUMMARY\>)? Recommended: \<MODE\>"**
  - "Dream Team" — Full orchestration with Opus architect + agents. Best for medium/large tickets.
  - "Lite" — Sonnet solo session, spawns agents only if needed. Same quality gates, lower cost. Best for small/medium tickets.
  - "Just worktree" — Create worktree only, no Claude session launched. User works on it manually or resumes later.

Save each choice for Phase B.

---

### Phase B: Sequential Launch (One Ticket at a Time)

For each ticket, run Steps 6-8 sequentially. Complete one ticket fully before starting the next.

#### Step 6: Pull Latest Main & Create Git Worktree

**Pull latest main once** before the first worktree (not per ticket):

```bash
cd ~/Documents/Repo && git checkout main && git pull origin main
```

Then for each ticket, create the worktree:

```bash
cd ~/Documents/Repo && git worktree add ~/Documents/<TICKET_ID> -b <TICKET_ID>
```

If the branch already exists:
```bash
cd ~/Documents/Repo && git worktree add ~/Documents/<TICKET_ID> <TICKET_ID>
```

#### Step 7: Install Dependencies & Copy Environment

```bash
cd ~/Documents/<TICKET_ID>/apps/web && source ~/.nvm/nvm.sh && nvm use && npm i
cp ~/Documents/Repo/apps/web/.env.local ~/Documents/<TICKET_ID>/apps/web/.env.local
```

#### Step 8: Write Pre-Hydrated Context File

Write the pre-hydration results from Step 3 to `.dream-team/context.md` in the worktree. This file is consumed by `/my-dream-team` to skip redundant exploration.

```bash
mkdir -p ~/Documents/<TICKET_ID>/.dream-team
```

Then write the file using the Write tool at `~/Documents/<TICKET_ID>/.dream-team/context.md` with this format:

```markdown
# Pre-Hydrated Context for <TICKET_ID>

Generated by /create-stories parallel pre-hydration.

## Ticket
<Full ticket text from Jira — summary, description, acceptance criteria>

## Scope
<backend-only | frontend-only | full-stack>

## Complexity
<small | medium | large>

## Key Files
- `<verified/path/to/file1.tsx>` — <what needs to change>
- `<verified/path/to/file2.cs>` — <what needs to change>

## Affected Services
- <service name> — <what's affected>

## Existing Patterns
- <pattern name>: `<path/to/example>` — <how to reuse>

## Conventions Summary
<Bullet points of key conventions from docs/ relevant to this ticket's scope>

## API Contract (if full-stack)
### <METHOD> <endpoint>
Request: <shape>
Response: <shape>

## Seed Data
<Available | Missing for X — needs to be added>

## Flags
- needs_testing: <true | false>
- needs_docker_rebuild: <true | false> (<service names>)

## Recommended Team
- <Agent>: <model> — <one-line justification>

## Hot File Conflicts
<List any hot files (AppRoutes.tsx, etc.) that this ticket touches>

## Attachment Notes
<Summary of what was seen in any downloaded attachments, or "No attachments">
```

#### Step 9: Launch Based on User's Choice (from Step 5)

**Check the user's terminal preference** in `~/.claude/CLAUDE.md` under "Workspace Preferences" for the configured terminal app.

**If "Dream Team"** (full orchestration):
```bash
bash ~/.claude/scripts/open-terminal.sh "<TERMINAL_APP>" "bash ~/.claude/scripts/launch-workspace.sh '<TICKET_ID>' '/my-dream-team <TICKET_SUMMARY>: <CONCISE_DESCRIPTION>'"
```

**If "Lite"** (Sonnet solo, same quality gates):
```bash
bash ~/.claude/scripts/open-terminal.sh "<TERMINAL_APP>" "bash ~/.claude/scripts/launch-workspace.sh '<TICKET_ID>' '/my-dream-team --lite <TICKET_SUMMARY>: <CONCISE_DESCRIPTION>'"
```

**If "Just worktree"** (no Claude session):
- Skip this step entirely. The worktree is already created from Steps 6-7.
- Tell the user the worktree is ready at `~/Documents/<TICKET_ID>` and they can start working manually or resume later with "resume \<TICKET_ID\>".

Replace `<TERMINAL_APP>` with the configured app (Alacritty, Terminal, iTerm, Warp, Kitty, WezTerm, or Ghostty).

**Important:** Escape any special characters (quotes, parentheses) in the ticket text. Keep the description concise.

#### Step 10: Repeat for Next Ticket

If there are more tickets, go back to Step 6 for the next ticket.

#### Step 11: Summary

After all tickets are launched, present a summary:
- List all created workspaces with their ticket IDs and tmux session names
- Show which mode each ticket is running in (Dream Team / Lite / Just worktree)
- Remind the user they can attach to any session: `tmux attach -t <TICKET_ID>`
- Remind the user to run `/workspace-cleanup <TICKET_ID>` when done with each story (or they can say "clean up PROJ-1234" and you will handle it)

## Pausing a Workspace (Close for the Day)

When the user says "pause PROJ-1234", "close PROJ-1234", "stop for today", or "kill the session":

```bash
bash ~/.claude/scripts/pause-workspace.sh <TICKET_ID>
```

This kills the tmux session and any Vite dev servers, but **preserves everything else**: worktree, code, `.dream-team/` notes/journals, git branches, and the draft PR. The user can resume the next day.

To pause **all running workspaces**:
```bash
for session in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^PROJ-'); do
  bash ~/.claude/scripts/pause-workspace.sh "$session"
done
```

## Resuming a Workspace

When the user says "resume PROJ-1234" or "pick up PROJ-1234" or "continue PROJ-1234":

1. **Verify the worktree exists**:
   ```bash
   cd ~/Documents/Repo && git worktree list | grep <TICKET_ID>
   ```
   If not found, tell the user the worktree doesn't exist.

2. **Check the user's terminal preference** in `~/.claude/CLAUDE.md` under "Workspace Preferences".

3. **Launch with the resume script**:

   ```bash
   bash ~/.claude/scripts/open-terminal.sh "<TERMINAL_APP>" "bash ~/.claude/scripts/resume-workspace.sh '<TICKET_ID>'"
   ```

   Replace `<TERMINAL_APP>` with the configured app from Workspace Preferences.

4. **Confirm** to the user that the workspace is resuming. Remind them to `tmux attach -t <TICKET_ID>`.

## Monitoring & Cleanup

### Check workspace status

The user can ask "how are the workspaces doing?" or "check status". Check for status files and tmux sessions:

```bash
# Check for completed workspaces (status files written by Dream Teams)
ls ~/.claude/workspace-status/*.json 2>/dev/null && cat ~/.claude/workspace-status/*.json

# Check which tmux sessions are running
tmux list-sessions 2>/dev/null

# Check which worktrees exist
cd ~/Documents/Repo && git worktree list
```

Report a summary table showing each workspace's status (running / done-awaiting-merge / no session).

### When the user says "it's merged" or "clean up"

When the user indicates a story is done or merged (e.g., "PROJ-1234 is merged", "clean up PROJ-1234", "that story is finished"):

1. **Check the status file** (if exists):
   ```bash
   cat ~/.claude/workspace-status/<TICKET_ID>.json 2>/dev/null
   ```

2. **Run cleanup from this orchestrator session** (NOT from inside the worktree). Execute these steps directly — do NOT delegate to `/workspace-cleanup` since we're already in the orchestrator:

   ```bash
   # Safety: check PR status first
   cd ~/Documents/Repo && gh pr list --head <TICKET_ID> --state all --json number,state,mergedAt,title

   # Kill tmux session if running
   tmux kill-session -t <TICKET_ID> 2>/dev/null || true

   # Remove worktree (we're in Repo, not inside the worktree)
   cd ~/Documents/Repo && git worktree remove ~/Documents/<TICKET_ID> --force

   # Clean up leftover directory
   rm -rf ~/Documents/<TICKET_ID>

   # Delete branch (ask user first if PR is not merged)
   cd ~/Documents/Repo && git branch -D <TICKET_ID>

   # Prune worktree references
   cd ~/Documents/Repo && git worktree prune

   # Remove status file
   rm -f ~/.claude/workspace-status/<TICKET_ID>.json
   ```

3. **If PR is NOT merged**, warn the user before proceeding — code may only exist on the remote branch.

4. **Confirm** by showing the updated worktree list.

### Bulk cleanup

When the user says "clean up all done workspaces" or similar:
1. Read all status files from `~/.claude/workspace-status/`
2. For each with `"status": "done"`, check PR merge status
3. Clean up all that are merged (or user-confirmed)
4. Show summary of what was cleaned

## Important Rules

- Always confirm extracted ticket info with the user before creating worktrees
- The main repo is always at `~/Documents/Repo`
- Worktrees are always at `~/Documents/<TICKET_ID>`
- tmux sessions are always named `<TICKET_ID>`
- If anything fails, stop and report — do not continue blindly
- For Jira attachments, use `~/.claude/scripts/jira-download-attachments.sh` (API download via ACLI OAuth token). Falls back to Chrome if API fails.
- **Phase A** (pre-hydration) runs in parallel across all tickets — Phase B (worktree creation + launch) runs sequentially one ticket at a time
- When sending ticket text via tmux send-keys, keep it concise if the description is very long — include the essential description and acceptance criteria
