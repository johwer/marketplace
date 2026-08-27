#!/usr/bin/env bash
# pr-body-gate.sh — fail-closed check on the human-facing part of a PR description.
#
# Repo DTF only. Runs immediately before `gh pr ready`, and again in the Phase 7
# Completion Gate. Refuses (exit 1) when the body still carries session scaffolding or
# has grown past the point where a human reads it.
#
# Usage:  bash ~/.claude/scripts/pr-body-gate.sh <PR_NUMBER>
#
# Exit codes:
#   0  passed, or deliberately out of scope (not the Repo repo)
#   1  REFUSED — the body needs the pr-ready skill run on it
#
# Env overrides (rarely needed):
#   PR_GATE_REPO         default RepoAB/Repo
#   PR_GATE_WORD_LIMIT   default 250
#
# NOTE ON `set -e`: deliberately NOT used. Every check must run so the operator sees the
# full list of violations in one pass, and a failed check must REFUSE rather than let the
# script exit successfully at the point of failure.
set -uo pipefail

REPO_ALLOW="${PR_GATE_REPO:-RepoAB/Repo}"
WORD_LIMIT="${PR_GATE_WORD_LIMIT:-250}"
WORD_TARGET=180

PR="${1:-}"

# --- Sections that must not survive the ready transition -------------------------------
# Session scaffolding, reviewer detail that belongs in the notes comment, and audiences
# served elsewhere (test guide -> Jira via tester-handoff).
#
# `Decisions` is on this list deliberately. An OPEN domain-model decision belongs in the
# body — but you should not be going ready with one unresolved. If this refuses on a live
# open gate, the answer is to resolve the gate, not to soften the pattern.
BANNED_HEADINGS='Progress|Architecture|How to Test|Questions|Walkthrough of the changes|Reading this diff|Pre-emptive review|Pre-emptive Review|Verification|Verified, not assumed|Runtime verification|Decisions|Also landed|What the audit turned up|Deliberately left behind|All [0-9]+ bumps|Pre-existing issues'

# --- Draft placeholder text that must have been replaced -------------------------------
PLACEHOLDERS=(
  '1-3 sentences'
  '2-5 bullets'
  'No open questions yet'
  'POWER BY'
  'Any other setup needed'
  'Step-by-step user actions'
  'Another verification point'
)

fail=()
warn=()

refuse() {
  printf '\n'
  if [ "${#fail[@]}" -gt 0 ]; then
    for f in "${fail[@]}"; do printf '  \033[31m✗\033[0m %s\n' "$f"; done
  fi
  printf '\n  \033[31mREFUSED\033[0m — run the pr-ready skill on PR #%s\n\n' "$PR"
  exit 1
}

# --- 0. Arguments ----------------------------------------------------------------------
# A gate that cannot identify its target must refuse, not pass.
if ! printf '%s' "$PR" | grep -qE '^[0-9]+$'; then
  printf '  \033[31m✗\033[0m usage: pr-body-gate.sh <PR_NUMBER>\n' >&2
  exit 1
fi

# --- 1. Scope: Repo repo only -------------------------------------------------------
# Out of scope exits 0 (this gate has no opinion about other repos). But an UNKNOWN repo
# is a failed check, not an out-of-scope one, so it refuses.
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
rc=$?
if [ "$rc" -ne 0 ] || [ -z "$repo" ]; then
  fail+=("cannot determine the repo (gh not authenticated?) — refusing rather than assuming")
  refuse
fi
if [ "$repo" != "$REPO_ALLOW" ]; then
  printf '  \033[33m—\033[0m out of scope: %s is not %s, gate skipped\n' "$repo" "$REPO_ALLOW"
  exit 0
fi

# --- 2. Fetch the body -----------------------------------------------------------------
body_raw=$(gh pr view "$PR" --json body --jq .body 2>/dev/null)
rc=$?
if [ "$rc" -ne 0 ]; then
  fail+=("could not fetch PR #$PR body")
  refuse
fi
if [ -z "$body_raw" ]; then
  fail+=("PR #$PR has an empty body")
  refuse
fi

tmp=$(mktemp -t prbodygate)
printf '%s\n' "$body_raw" >"$tmp"
trap 'rm -f "$tmp" "$tmp.stripped"' EXIT

# --- 3. Strip what does not count toward the word budget -------------------------------
# Images and their markup, collapsed <details> blocks, HTML comments and fenced code.
# Captions are prose a human reads, so they are NOT stripped — only the markup lines.
awk '
  /^```/            { infence = !infence; next }
  infence           { next }
  /<!--/            { incomment = 1 }
  incomment         { if ($0 ~ /-->/) incomment = 0; next }
  /<details/        { indetails = 1; next }
  indetails         { if ($0 ~ /<\/details>/) indetails = 0; next }
  /<img|!\[/        { next }
  /^<pre>|^<\/pre>/ { next }
  { print }
' "$tmp" >"$tmp.stripped"

# --- 4. Banned headings ----------------------------------------------------------------
banned_hits=$(grep -nEi "^#{1,4} +(${BANNED_HEADINGS})" "$tmp" 2>/dev/null)
if [ -n "$banned_hits" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    fail+=("banned section: $(printf '%s' "$line" | sed 's/^\([0-9]*\):/line \1: /')")
  done <<<"$banned_hits"
fi

# --- 5. Required headings --------------------------------------------------------------
for required in '## Why' '## What changes'; do
  if ! grep -qF "$required" "$tmp"; then
    fail+=("missing required section: $required")
  fi
done

# --- 6. Draft placeholders and the banner ----------------------------------------------
for p in "${PLACEHOLDERS[@]}"; do
  if grep -qF "$p" "$tmp"; then
    fail+=("draft placeholder still present: \"$p\"")
  fi
done
if grep -q '█' "$tmp"; then
  fail+=("ASCII banner still in the body — strip it at ready")
fi

# --- 7. Word budget -------------------------------------------------------------------
words=$(wc -w <"$tmp.stripped" | tr -d ' ')
if ! printf '%s' "$words" | grep -qE '^[0-9]+$'; then
  fail+=("could not count words — refusing rather than assuming")
  refuse
fi
if [ "$words" -gt "$WORD_LIMIT" ]; then
  fail+=("body $words words (limit $WORD_LIMIT, target $WORD_TARGET) — move detail to the notes comment")
elif [ "$words" -gt "$WORD_TARGET" ]; then
  warn+=("body $words words — over the $WORD_TARGET target but under the $WORD_LIMIT cap")
fi

# --- 8. The notes comment must exist if detail was moved out ---------------------------
# Only a warning: a genuinely tiny PR has nothing to move.
notes=$(gh pr view "$PR" --json comments --jq '[.comments[]?.body | select(test("pr-ready:notes"))] | length' 2>/dev/null)
if printf '%s' "$notes" | grep -qE '^[0-9]+$' && [ "$notes" -eq 0 ]; then
  warn+=("no 'Implementation notes — reviewer detail' comment found (fine if there was no detail to move)")
fi

# --- 9. Verdict ------------------------------------------------------------------------
if [ "${#fail[@]}" -gt 0 ]; then
  refuse
fi

printf '  \033[32m✓\033[0m PR #%s body: %s words, no banned sections\n' "$PR" "$words"
if [ "${#warn[@]}" -gt 0 ]; then
  for w in "${warn[@]}"; do printf '  \033[33m!\033[0m %s\n' "$w"; done
fi
exit 0
