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

### Cost Model: Pre-hydration vs Amara

Pre-hydration looks expensive in isolation (30-90k tokens per ticket) but it **replaces** most of Amara's Phase 1 work. The trade-off:

| Without pre-hydration | With pre-hydration |
|---|---|
| Amara does full exploration: ~80-120k tokens | Pre-hydration: ~30-50k tokens (capped at 30 tool uses) |
| Sequential (one ticket at a time) | Parallel (all tickets simultaneously) |
| Each Amara session on Opus (~19x cost) | Pre-hydration on Sonnet (~4x cost), Amara validates on Opus (~30% of full) |

**Net savings:** Pre-hydration costs ~40% of what a full Amara analysis would cost, and it runs in parallel. A session that previously needed 120k tokens for Amara now needs ~50k pre-hydration + ~30k Amara validation = ~80k total, but the pre-hydration happened concurrently with other tickets.

**Budget cap:** Pre-hydration agents are capped at **30 tool uses** to prevent runaway exploration. If a ticket needs more than 30 tool uses to triage, it's complex enough that Amara should handle the full analysis anyway.

**Phase cost tracking:** After pre-hydration completes, log the costs:
```bash
bash ~/.claude/scripts/phase-cost-tracker.sh log "<TICKET_ID>" "pre-hydration" "explore" "<tool_uses>" "<scope>"
```

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

5. **Memory health check** — run the bash script (0 token cost) and report if action is needed:
   ```bash
   bash ~/.claude/scripts/memory-health.sh
   ```
   If it reports warnings (MEMORY.md over budget, dream-team-learnings > 500 lines, stale files), show the output and ask:
   > Memory health check found [N] suggestion(s). Want me to clean up now, or skip and continue?

   If they say yes, use the `memory-hygiene` skill to handle it. If no, proceed — don't nag.

6. **Also kill any orphan tmux sessions** that don't have a matching worktree:
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

#### Step 1.5: Quick Triage Checkpoint (User Decision Gate)

**Before spending tokens on pre-hydration**, present the ticket summaries from Step 1 and let the user decide which tickets to proceed with. The user often has context that's NOT in the ticket — blocked dependencies, wrong priority, needs refinement first, or "I already know this is a 5-minute fix".

Present a **rich summary** per ticket using the Jira data from Step 1 — enough for the user to make an informed decision without codebase exploration:

```
## Quick Triage — Which tickets should we pre-analyze?

### 1. PROJ-1234 — Add mobile number field to employee card
- **Status:** To Do  |  **Story Points:** 3  |  **Sprint:** Sprint 14
- **Description:** Add a mobile phone field to the employee contact section. Should be editable by HR admins and visible on the employee card.
- **Acceptance Criteria:**
  - Field visible on employee card under contact section
  - Editable only by users with HR Admin permission
  - Validation: Swedish mobile format (+46...)
- **Attachments:** 1 image (mockup)
- **Labels/Components:** frontend, service-b

### 2. PROJ-1235 — Fix date picker styling on service-a form
- **Status:** To Do  |  **Story Points:** 1  |  **Sprint:** Sprint 14
- **Description:** Date picker overlaps the submit button on mobile viewport.
- **Acceptance Criteria:** Date picker renders correctly on all viewports
- **Attachments:** none
- **Labels/Components:** frontend, service-a

### 3. PROJ-1236 — Update seed data for test environments
- **Status:** Blocked  |  **Story Points:** —  |  **Sprint:** Backlog
- **Description:** Add new test customers with specific permission configurations.
- **Blocked by:** PROJ-1200 (ServiceC migration not complete)
```

Ask the user with AskUserQuestion:

**"Which tickets should we pre-analyze? (each GO costs ~30-50k tokens on Sonnet)"**
- **GO** — Pre-hydrate and launch (default)
- **SKIP** — Don't pre-hydrate, don't launch. Ticket stays as-is.
- **JUST WORKTREE** — Create worktree only, skip pre-hydration. For tickets the user already knows are trivial.
- **REFINE FIRST** — Ticket needs work before implementation. Optionally run `/ticket-refine` on it.

**Why this matters:**
- Pre-hydration costs 30-50k tokens per ticket on Sonnet
- A ticket the user knows is blocked = 50k wasted tokens
- A ticket the user knows is a 2-line fix = 50k wasted tokens (just create a worktree)
- The user may have context about dependencies, priorities, or blockers that aren't in Jira

**Only proceed with GO tickets to Step 2.** SKIP tickets are removed from the pipeline. JUST WORKTREE tickets skip to Phase B Step 6 directly. REFINE FIRST tickets are queued for `/ticket-refine` after the session.

---

#### Step 2: Handle Attachments

After all tickets are fetched, download attachments **only for GO tickets**.

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

#### Step 3: Pre-Hydrate GO Ticket Contexts (Parallel)

Spawn **parallel explore agents** (one per ticket, subagent_type `Explore`, model `sonnet`) to analyze each ticket against the codebase. Each agent receives the ticket info from Step 1 and runs a **budget-capped** lightweight version of Amara's Phase 1 analysis.

**Budget cap: max 30 tool uses per pre-hydration agent.** Pre-hydration is NOT a full Amara analysis — it's a quick triage to determine scope, key files, and recommended mode. The full analysis happens later in Phase 1 of `/my-dream-team`. If the agent is still exploring at 25 tool uses, it MUST wrap up and return what it has.

**Efficiency rules for pre-hydration agents:**
- Use Glob FIRST (folder names), then Grep only if Glob is ambiguous — most scope questions are answered by folder structure alone
- Do NOT read full convention docs — just note which docs apply (e.g., "CODING_STYLE_BACKEND.md needed") and let Amara read them later
- Do NOT write full API contracts — just note "full-stack, needs API contract" and let Amara define it
- Do NOT verify every file path — verify the top 3-5 key files, note the rest as "likely path"
- If the ticket is clearly small (1-2 files, single area), return after 10-15 tool uses — don't over-explore

```
For each ticket, spawn an explore agent with this prompt:

"You are pre-analyzing ticket <TICKET_ID> for the Repo monorepo at ~/Documents/Repo.

BUDGET: You have max 30 tool uses. This is a QUICK TRIAGE, not a full architecture analysis. Prioritize breadth over depth — determine scope, find key files, recommend a mode. Stop exploring when you have enough to recommend.

Ticket: <FULL_TICKET_TEXT_FROM_STEP_1>

Analyze the codebase to determine:
1. **Scope**: backend-only, frontend-only, or full-stack
2. **Complexity**: small (1-3 files), medium (4-8 files), large (8+ files)
3. **Key files**: List the main files that will need modification (verify top 3-5 paths with Glob, note others as likely)
4. **Affected services**: Which services/areas of the codebase are involved
5. **Dependencies**: Does this ticket conflict with hot files (AppRoutes.tsx, EmployeeCardTabs.tsx)?
6. **Existing patterns**: Quick Glob/Grep for reusable components — don't deep-read them
7. **Conventions note**: Which docs/ files apply (don't read them, just note them)
8. **API contract note** (if full-stack): Note 'needs API contract from Amara' — don't define it yourself
9. **Seed data**: Quick check if seed data exists for the entities involved
10. **Needs testing**: yes/no with one-line reason
11. **Needs Docker rebuild**: Which service(s), if any
12. **Recommended mode**: Dream Team / Lite / Just worktree — with one-line justification
13. **Recommended team**: Which agents at what model tier

Return your analysis as a structured report. If you haven't finished all 13 points by tool use 25, wrap up with what you have — partial is fine, Amara will fill gaps."
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

#### Step 3.5: Create ALL Worktrees (Parallel with Pre-Hydration)

**Worktree creation is deterministic — zero LLM tokens.** Start creating worktrees for ALL GO + JUST WORKTREE tickets immediately after triage, IN PARALLEL with Step 3 (pre-hydration). Don't wait for pre-hydration to finish.

**Pull latest main once** before creating any worktrees:

```bash
cd ~/Documents/Repo && git checkout main && git pull origin main
```

**Then create ALL worktrees in sequence** (git worktree add is fast, ~2 seconds each):

```bash
# For each GO or JUST WORKTREE ticket:
cd ~/Documents/Repo && git worktree add ~/Documents/<TICKET_ID> -b <TICKET_ID>

# If the branch already exists:
cd ~/Documents/Repo && git worktree add ~/Documents/<TICKET_ID> <TICKET_ID>
```

**Install dependencies in each** (can run in parallel via background jobs):

```bash
# For each worktree (run these in parallel with &):
(cd ~/Documents/<TICKET_ID>/apps/web && source ~/.nvm/nvm.sh && nvm use && npm i) &
```

**Copy environment files + allocate ports:**

```bash
# For each worktree:
cp ~/Documents/Repo/apps/web/.env.local ~/Documents/<TICKET_ID>/apps/web/.env.local
bash ~/.claude/scripts/allocate-ports.sh <TICKET_ID>
```

Wait for all `npm i` background jobs to finish before proceeding.

**Why this matters:** `npm i` takes 30-60 seconds per worktree. If you have 4 tickets, that's 2-4 minutes — which now runs DURING pre-hydration instead of AFTER it. By the time pre-hydration returns, all worktrees are ready.

#### Step 5: User Confirms Launch Mode Per GO Ticket

Pre-hydration (Step 3) and worktree creation (Step 3.5) should both be complete by now. For each **GO** ticket, confirm the implementation mode based on pre-hydration analysis:

- **"Launch mode for \<TICKET_ID\> (\<SUMMARY\>)? Recommended: \<MODE\>"**
  - **"Dream Team"** — Full orchestration with Opus architect + agents. Best for medium/large tickets.
  - **"Lite"** — Sonnet solo session, spawns agents only if needed. Same quality gates, lower cost. Best for small/medium tickets.

Note: "Just worktree" tickets were already separated in Step 1.5 — their worktrees are already created from Step 3.5.

Save each choice for Phase B.

---

### Phase B: Write Context & Launch (One Ticket at a Time)

Worktrees already exist from Step 3.5. Phase B only writes context files and opens terminals — much faster than before.

#### Step 6: Write Jira Ticket & Pre-Hydrated Context Files

First, write the full Jira ticket to disk. This is the **single source of truth** that every agent reads from.

```bash
mkdir -p ~/Documents/<TICKET_ID>/.dream-team
```

Use the Write tool to create `~/Documents/<TICKET_ID>/.dream-team/jira-ticket.md` with the full Jira output from Step 1 (summary, description, acceptance criteria, attachments, raw acli output). This file persists in the worktree and is read by every agent — no more pasting ticket text into prompts.

Then write the pre-hydration results from Step 3 to `.dream-team/context.md` in the worktree. This file is consumed by `/my-dream-team` to skip redundant exploration.

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

## Worktree Port & Translations
This worktree's Vite dev server port: `<VITE_DEV_PORT from .env.local>` (e.g., http://localhost:31XX)
S3 translations work on all 3xxx ports (CORS: `http://localhost:3*`) — no need for port 3000.
Multiple worktrees can run Playwright verification simultaneously on different ports.

## Visual Verification — Playwright CLI (include for frontend-only or full-stack tickets)
Use the `playwright-cli` skill for ALL browser verification. Do NOT use Puppeteer MCP tools — those are deprecated.

\```bash
# Open browser with named session (use the worktree's port from .env.local)
playwright-cli -s=lena open http://localhost:<VITE_DEV_PORT>/<path> --headed

# Take snapshot to get element refs
playwright-cli -s=lena snapshot

# Interact
playwright-cli -s=lena click <ref>
playwright-cli -s=lena fill <ref> "value"

# Screenshot
playwright-cli -s=lena screenshot --filename=<TICKET_ID>-after.png

# Video recording
playwright-cli -s=lena video-start
# ... do interactions ...
playwright-cli -s=lena video-stop <TICKET_ID>-after.webm

# Close when done
playwright-cli -s=lena close
\```

Login sequence: click "More login options" → "Username and password" → fill username (gunner/anna) → fill password (tolvan) → submit.
Screenshots go to `~/Downloads/<TICKET_ID>-*.png`. This is NOT optional for UI changes.
```

#### Step 7: Launch Based on User's Choice (from Step 5)

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

#### Step 8: Repeat for Next Ticket

If there are more GO tickets, go back to Step 6 for the next ticket.

#### Step 9: Summary

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

   # Kill Vite/Node dev servers for this worktree (prevents orphan processes holding ports)
   PIDS=$(pgrep -f "node.*<TICKET_ID>" 2>/dev/null || true)
   [ -z "$PIDS" ] && PIDS=$(lsof -i -P 2>/dev/null | grep node | grep LISTEN | grep "<TICKET_ID>" | awk '{print $2}' | sort -u || true)
   [ -n "$PIDS" ] && echo "$PIDS" | xargs kill 2>/dev/null || true

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
