# Workspace Cleanup — Remove Worktree, Folder & Branch

Tear down a workspace that was created by `/workspace-launch`.

## Config Resolution

Read `~/.claude/dtf-config.json` if it exists. Use:
- `paths.monorepo` instead of `~/Documents/Repo`
- `paths.worktreeParent` instead of `~/Documents`
If no config exists, fall back to the values in `~/.claude/CLAUDE.md`.

## Input

The user provides a ticket ID (e.g., `PROJ-1234`). If not provided, list existing worktrees and ask which one to clean up.

$ARGUMENTS

## Workflow

### Step 0: Ensure We're Not Inside the Worktree

**CRITICAL:** If the current working directory is inside the worktree being cleaned up (e.g., `~/Documents/PROJ-1234`), you MUST `cd ~/Documents/Repo` first. Git cannot remove a worktree while a process has its cwd inside it. Always run all cleanup commands from `~/Documents/Repo`.

```bash
cd ~/Documents/Repo
```

### Step 1: Identify Worktree

If no ticket ID was provided, list worktrees:

```bash
cd ~/Documents/Repo && git worktree list
```

Ask the user which one to remove.

### Step 2: Safety Check — PR Status

Before any destructive action, check if there's an open PR for this branch:

```bash
cd ~/Documents/Repo && gh pr list --head <TICKET_ID> --state all --json number,state,mergedAt,title
```

**Based on PR status:**
- **Merged** — Safe to clean up. Proceed to unresolved thread check below.
- **Open (not merged)** — **STOP.** Tell the user: "PR #NNN is still open and not merged. Are you sure you want to remove the worktree? The code will only exist on the remote branch." Only proceed if they confirm.
- **No PR found** — **STOP.** Tell the user: "No PR found for this branch. Any uncommitted or unpushed work will be lost." Only proceed if they confirm.
- **Closed (not merged)** — Warn the user the PR was closed without merging, confirm before proceeding.

**Unresolved review thread check** — run this for any PR (merged or open) before proceeding:

```bash
gh api graphql -f query='{ repository(owner: "<OWNER>", name: "<REPO>") { pullRequest(number: <PR_NUMBER>) { reviewThreads(first: 50) { nodes { id isResolved comments(first: 1) { nodes { body author { login } } } } } } } }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .comments.nodes[0].body'
```

If any unresolved threads are found, **STOP** and tell the user which comments are still open. Do not proceed until the user confirms they're aware. Reminder: every comment needs a **reply** (explaining what was done or pushing back) AND a **resolve** — not just one or the other.

### Step 3: Stop Worktree Docker Services (if running)

If the worktree has a `docker-compose.worktree.yml`, stop any running worktree containers:

```bash
cd ~/Documents/<TICKET_ID> && docker compose -f docker-compose.worktree.yml down 2>/dev/null || true
```

### Step 4: Kill Vite Dev Server & tmux Session

Before removing the worktree, check if there's a Vite dev server running on its allocated port and ask the user whether to kill it.

```bash
# Read the allocated port from the worktree's .env.local
VITE_PORT=$(grep VITE_DEV_PORT ~/Documents/<TICKET_ID>/apps/web/.env.local 2>/dev/null | cut -d= -f2)

# Check if anything is listening on that port
if [ -n "$VITE_PORT" ]; then
  PORT_PID=$(lsof -ti tcp:$VITE_PORT 2>/dev/null || true)
fi
```

**If a process is found on the port**, tell the user: "Vite dev server is still running on port `$VITE_PORT` (PID $PORT_PID). Kill it?" and kill it if they confirm:

```bash
kill $PORT_PID 2>/dev/null || true
```

**If no port is found or nothing is listening**, skip silently.

Then kill the tmux session regardless:

```bash
tmux kill-session -t <TICKET_ID> 2>/dev/null || true
```

### Step 5: Check for Uncommitted Work

```bash
cd ~/Documents/<TICKET_ID> && git status --porcelain
```

If there are uncommitted changes, **STOP** and tell the user. Only proceed if they confirm.

### Step 6: Remove Git Worktree

```bash
cd ~/Documents/Repo && git worktree remove ~/Documents/<TICKET_ID> --force
```

### Step 7: Clean Up Directory (if leftover)

This also removes `.dream-team/` notes, journals, and any other leftover files.

```bash
rm -rf ~/Documents/<TICKET_ID>
```

### Step 8: Delete the Branch

Ask the user if they want to delete the branch too. If the PR is merged, suggest yes. If not merged, suggest no.

If yes:
```bash
cd ~/Documents/Repo && git branch -D <TICKET_ID>
```

### Step 9: Prune Worktree References

```bash
cd ~/Documents/Repo && git worktree prune
```

### Step 10: Confirm

Show the updated worktree list:

```bash
cd ~/Documents/Repo && git worktree list
```

## Important Rules

- **Never delete a worktree without checking PR status first**
- Always confirm with the user before deleting the branch
- If PR is open/unmerged, default to keeping both worktree and branch — user must explicitly confirm deletion
- The main repo is always at `~/Documents/Repo`
- If the worktree directory doesn't exist, skip the removal step and just clean up the branch
