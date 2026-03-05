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
- **Merged** — Safe to clean up. Proceed.
- **Open (not merged)** — **STOP.** Tell the user: "PR #NNN is still open and not merged. Are you sure you want to remove the worktree? The code will only exist on the remote branch." Only proceed if they confirm.
- **No PR found** — **STOP.** Tell the user: "No PR found for this branch. Any uncommitted or unpushed work will be lost." Only proceed if they confirm.
- **Closed (not merged)** — Warn the user the PR was closed without merging, confirm before proceeding.

### Step 3: Stop Worktree Docker Services (if running)

If the worktree has a `docker-compose.worktree.yml`, stop any running worktree containers:

```bash
cd ~/Documents/<TICKET_ID> && docker compose -f docker-compose.worktree.yml down 2>/dev/null || true
```

### Step 4: Kill tmux Session (if running)

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

### Step 9.5: Remove Status File (if exists)

```bash
rm -f ~/.claude/workspace-status/<TICKET_ID>.json
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
