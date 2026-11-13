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

If the current working directory is inside the worktree being cleaned up (e.g., `~/Documents/PROJ-1234`), `cd ~/Documents/Repo` first. Git cannot remove a worktree while a process has its cwd inside it. Always run all cleanup commands from `~/Documents/Repo`.

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

### Step 3: Check for Uncommitted Work

Before anything is stopped or deleted:

```bash
git -C ~/Documents/<TICKET_ID> status --porcelain
```

If there are uncommitted changes, **STOP** and tell the user. Only proceed if they confirm.

### Step 4: Ask About the Branch

Ask the user if they want to delete the branch too. If the PR is merged, suggest yes. If not merged, suggest no.

### Step 5: Tear Down

One script does the whole teardown, the same one `/create-stories` uses: bridge archive, worktree services, this worktree's Vite and Cosmos processes (only those whose cwd is inside the worktree), tmux session, this ticket's containers, images and named volumes (matched on the exact ticket id, so `PROJ-48` never touches `PROJ-4880`), the worktree and its directory (including `.dream-team/`), `git worktree prune`, and the workspace status file.

```bash
bash ~/.claude/scripts/cleanup-workspace.sh <TICKET_ID> [--delete-branch] [--discard-local-work]
```

- `--delete-branch` only if the user said yes in Step 4.
- `--discard-local-work` only if the user confirmed in Step 3 or Step 2 (no PR) that local work may be lost. Without it the script refuses with exit 3 when it finds uncommitted work or commits not pushed to the upstream branch, and touches nothing.
- `--dry-run` prints what would be removed.

Paste the output. It ends with the updated `git worktree list`.

> A periodic `bash ~/.claude/scripts/docker-cleanup.sh --orphan-worktrees` reclaims named volumes from any worktrees that were removed without this step.

## Important Rules

- **Never delete a worktree without checking PR status first**
- Always confirm with the user before deleting the branch
- If PR is open/unmerged, default to keeping both worktree and branch — user must explicitly confirm deletion
- The main repo is always at `~/Documents/Repo`
- If the worktree directory doesn't exist, the script skips the worktree steps and still cleans up containers, refs and the branch
