#!/usr/bin/env bash
# rebase-and-regate.sh — rebase onto origin/main and re-run quality-gate.sh until the branch is
# fresh AND green, or a real failure / conflict stops it.
#
# Usage: bash ~/.claude/scripts/rebase-and-regate.sh <WORKTREE> [MAX_ROUNDS=3]
#
# Why: on a busy main the freshness check refuses the push, you rebase, the gate takes minutes, and
# main has moved again (PROJ-4472: refused twice in a row). This loops the round-trip. It does NOT
# push — on success it prints the push command, so the `gate && push` chain stays with the caller.
#
# Exit 0 = fresh and green. 1 = gate failed for a reason other than freshness, or rebase conflict.
# 2 = usage / dirty tree. 3 = still behind after MAX_ROUNDS.
set -uo pipefail

WT="${1:?Usage: rebase-and-regate.sh <WORKTREE> [MAX_ROUNDS]}"
MAX="${2:-3}"
cd "$WT" || exit 2

# A dirty tree cannot be rebased. Never a bare `git stash` here: worktrees share the stash list.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "✗ uncommitted changes in $WT — commit them (or move them out with a patch) before rebasing"
  git status --short | head -10
  exit 2
fi

behind() {
  git fetch -q origin main || { echo "✗ git fetch origin main failed"; exit 1; }
  [ "$(git merge-base HEAD origin/main)" != "$(git rev-parse origin/main)" ]
}

for round in $(seq 1 "$MAX"); do
  echo "▸ round $round/$MAX"
  if behind; then
    echo "  origin/main moved — rebasing"
    if ! git rebase origin/main; then
      git rebase --abort
      echo "✗ rebase conflict — resolve manually (rebase aborted, branch unchanged)"
      exit 1
    fi
  fi
  bash ~/.claude/scripts/quality-gate.sh "$WT"
  RC=$?
  if [ "$RC" -eq 0 ]; then
    echo "✓ fresh and green — push now: git push --force-with-lease origin HEAD"
    exit 0
  fi
  if behind; then
    echo "  gate failed and origin/main moved during the run — going again"
    continue
  fi
  echo "✗ quality gate failed for a reason other than freshness (rc=$RC) — fix it, do not loop"
  exit 1
done
echo "✗ still behind after $MAX rounds — main is very busy; try again shortly"
exit 3
