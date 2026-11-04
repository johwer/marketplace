#!/usr/bin/env bash
# pr-body-shape.sh — which PR body shape a repo expects. Prints one word and exits 0:
#
#   template  the repo's .github/pull_request_template.md has `## Summary` and `## Agent`
#             (Repo since #4470): Summary → Visual verification → Considerations → Agent
#   dtf       no such template (other repos, other DTF users, older Repo):
#             Why → What changes → Visual verification → Scope
#
# The template is read from the repo's default branch, so a template change needs no DTF change.
# Exits 1 (and prints nothing on stdout) when the template cannot be read for a reason other
# than "there is none" — callers must refuse rather than guess the shape.
#
# Usage:  bash ~/.claude/scripts/pr-body-shape.sh [OWNER/REPO]   (default: the current repo)
set -uo pipefail

repo="${1:-}"
if [ -z "$repo" ]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
  if [ -z "$repo" ]; then
    echo "pr-body-shape: cannot determine the repo (gh not authenticated, or not in a repo)" >&2
    exit 1
  fi
fi

out=$(gh api "repos/$repo/contents/.github/pull_request_template.md" \
  -H 'Accept: application/vnd.github.raw' 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  if grep -q 'HTTP 404' <<<"$out"; then
    echo dtf
    exit 0
  fi
  echo "pr-body-shape: could not read $repo's PR template: $out" >&2
  exit 1
fi

template=$(tr -d '\r' <<<"$out")
if grep -q '^## Summary' <<<"$template" && grep -q '^## Agent' <<<"$template"; then
  echo template
else
  echo dtf
fi
