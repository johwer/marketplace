#!/usr/bin/env bash
# rebase-and-regate.sh — rebase onto the PR's base and re-run quality-gate.sh until the branch is
# fresh AND green, or a real failure / conflict stops it.
#
# Usage: bash ~/.claude/scripts/rebase-and-regate.sh <WORKTREE> [MAX_ROUNDS=3]
#   RR_BASE=<branch>   base to rebase onto (default: the PR's baseRefName via gh, else main)
#   OLD_BASE=<sha>     stacked branch whose base PR was squash-merged: replays only the commits
#                      after <sha> (the old base tip) onto origin/main — `git rebase --onto`.
#                      A plain rebase conflicts there, because the squash commit is not the
#                      base's commits (PROJ-4736).
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

BASE="${RR_BASE:-}"
if [[ -z "$BASE" && -z "${OLD_BASE:-}" ]] && command -v gh >/dev/null 2>&1; then
  BASE=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null || true)
fi
BASE="${BASE:-main}"
[[ -n "${OLD_BASE:-}" ]] && BASE=main

# A dirty tree cannot be rebased. Never a bare `git stash` here: worktrees share the stash list.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "✗ uncommitted changes in $WT — commit them (or move them out with a patch) before rebasing"
  git status --short | head -10
  if [[ "$(git diff --name-only; git diff --cached --name-only)" =~ ^([^[:space:]]*/)?package-lock\.json$ ]]; then
    cat <<'EOF'
  Only package-lock.json is dirty. On macOS that is usually npm dropping a Linux-only optional
  package (@swc/core-linux-x64-gnu), not your change (PROJ-4735, PROJ-4014):
    git diff -- '*package-lock.json' > <scratchpad>/lock.patch && git checkout -- '*package-lock.json'
  then re-run this script, then `npm ci`. Re-apply the patch ONLY if main did not touch dependencies —
  otherwise it reverts main's lockfile.
EOF
  fi
  exit 2
fi

if ! git fetch -q origin "$BASE"; then
  echo "✗ git fetch origin $BASE failed."
  if [[ "$BASE" != "main" ]]; then
    echo "  The base branch is gone — usually its PR was squash-merged. Re-run with the old base tip:"
    echo "  OLD_BASE=<sha of $BASE's last commit, e.g. from 'git log --oneline'> bash $0 $WT"
    echo "  and retarget the PR: gh pr edit --base main"
  fi
  exit 1
fi

behind() {
  git fetch -q origin "$BASE" || { echo "✗ git fetch origin $BASE failed"; exit 1; }
  [ "$(git merge-base HEAD "origin/$BASE")" != "$(git rev-parse "origin/$BASE")" ]
}

# `could not detach HEAD` (PROJ-4749, PROJ-4014, PROJ-3704): the target changes a file this worktree
# marks skip-worktree (the DTF section in AGENTS.md). Keep the flag: move the local copy aside,
# rebase, then put the target's version back with the local delta re-applied.
SAVE_DIR=$(mktemp -d)
declare -a MOVED=()
move_skip_worktree_aside() {
  local target="$1" f
  while IFS= read -r f; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    git diff --quiet HEAD "$target" -- "$f" && continue
    mkdir -p "$SAVE_DIR/$(dirname "$f")"
    git show "HEAD:$f" > "$SAVE_DIR/$f.orig" 2>/dev/null || : > "$SAVE_DIR/$f.orig"
    cp "$f" "$SAVE_DIR/$f.local"
    rm "$f"
    MOVED+=("$f")
    echo "  moved skip-worktree file aside: $f (upstream changed it)"
  done < <(git ls-files -v | awk '/^S /{print substr($0,3)}')
}
restore_skip_worktree() {
  local f
  for f in "${MOVED[@]+"${MOVED[@]}"}"; do
    git show "HEAD:$f" > "$SAVE_DIR/$f.new" 2>/dev/null || cp "$SAVE_DIR/$f.local" "$SAVE_DIR/$f.new"
    if git merge-file -p "$SAVE_DIR/$f.new" "$SAVE_DIR/$f.orig" "$SAVE_DIR/$f.local" > "$f"; then
      echo "  restored $f = new upstream + local delta (3-way merge)"
    else
      cp "$SAVE_DIR/$f.local" "$f"
      echo "  ! local delta conflicts with upstream in $f — kept the old local copy; upstream version: $SAVE_DIR/$f.new"
    fi
  done
  MOVED=()
}

rebase_once() {
  move_skip_worktree_aside "origin/$BASE"
  if [[ -n "${OLD_BASE:-}" ]]; then
    git rebase --onto origin/main "$OLD_BASE"
  else
    git rebase "origin/$BASE"
  fi
  local rc=$?
  [[ $rc -ne 0 ]] && git rebase --abort
  restore_skip_worktree
  return $rc
}

for round in $(seq 1 "$MAX"); do
  echo "▸ round $round/$MAX (base: origin/$BASE${OLD_BASE:+, --onto from ${OLD_BASE:0:9}})"
  if [[ -n "${OLD_BASE:-}" ]] || behind; then
    echo "  origin/$BASE moved — rebasing"
    if ! rebase_once; then
      echo "✗ rebase conflict — resolve manually (rebase aborted, branch unchanged)"
      exit 1
    fi
    OLD_BASE=""
  fi
  QG_BASE="$BASE" bash ~/.claude/scripts/quality-gate.sh "$WT"
  RC=$?
  if [ "$RC" -eq 0 ]; then
    if ! git diff --quiet HEAD; then
      echo "✗ gate passed but the tree is dirty — commit these before pushing:"
      git status --short | head -10
      exit 1
    fi
    echo "✓ fresh and green — push now: git push --force-with-lease origin HEAD"
    exit 0
  fi
  if behind; then
    echo "  gate failed and origin/$BASE moved during the run — going again"
    continue
  fi
  echo "✗ quality gate failed for a reason other than freshness (rc=$RC) — fix it, do not loop"
  exit 1
done
echo "✗ still behind after $MAX rounds — main is very busy; try again shortly"
exit 3
