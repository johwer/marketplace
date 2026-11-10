#!/usr/bin/env bash
# Usage: archive-live.sh <TICKET_ID> [worktree-path]
# Copies a worktree's bridge session (brief, advisor answers, log) to ~/.claude/bridge-eval/live/<TICKET_ID>/
# before the worktree is deleted. No-op when the ticket never ran bridge.
set -euo pipefail
ticket=$1
worktree="${2:-$HOME/Documents/$ticket}"
src="$worktree/.dream-team/bridge"
[[ -d $src ]] || { echo "bridge: nothing to archive for $ticket"; exit 0; }
dest="${BRIDGE_EVAL_DIR:-$HOME/.claude/bridge-eval}/live/$ticket"
mkdir -p "$dest"
cp -Rn "$src"/. "$dest"/
[[ -f $dest/expected.md ]] || echo "pending: write expected.md from the review threads after merge" > "$dest/PENDING"
echo "bridge: archived $ticket to $dest"
