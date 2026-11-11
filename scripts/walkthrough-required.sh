#!/usr/bin/env bash
# walkthrough-required.sh — read the plan-time needs_walkthrough decision for a DTF worktree.
#
# Usage: bash ~/.claude/scripts/walkthrough-required.sh [worktree]   (default: git toplevel of cwd)
# Prints exactly one of: true | false | unset | no-dtf
#   true    some plan file declares `needs_walkthrough: true` (true wins over false)
#   false   declared false, and nothing declares true
#   unset   a .dream-team/ exists but no file declares it
#   no-dtf  not a DTF worktree (no .dream-team/)
#
# Where it looks: .dream-team/context.md and .dream-team/notes/*.md. The architect (full mode)
# or the lead (lite mode, notes/team-lead.md) writes the line with a one-clause reason:
#   needs_walkthrough: true — blocked Registrera → answer → enabled → submit is a flow
# Exit code is always 0; callers decide what each value means.
set -uo pipefail

WT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DT="$WT/.dream-team"

if [ ! -d "$DT" ]; then
  echo "no-dtf"
  exit 0
fi

values=$( { grep -h -o -i -E 'needs_walkthrough[*`]*[ ]*[:=][*` ]*(true|false)' "$DT/context.md" "$DT"/notes/*.md 2>/dev/null || true; } \
  | grep -o -i -E '(true|false)$' | tr '[:upper:]' '[:lower:]')

if printf '%s\n' "$values" | grep -qx true; then
  echo "true"
elif printf '%s\n' "$values" | grep -qx false; then
  echo "false"
else
  echo "unset"
fi
exit 0
