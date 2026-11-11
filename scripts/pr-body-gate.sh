#!/usr/bin/env bash
# pr-body-gate.sh — fail-closed check on the human-facing part of a PR description.
#
# Repo DTF only. Runs immediately before `gh pr ready`, and again in the Phase 7
# Completion Gate. Refuses (exit 1) when the body still carries session scaffolding or
# has grown past the point where a human reads it.
#
# Usage:  bash ~/.claude/scripts/pr-body-gate.sh <PR_NUMBER>
#
# Body shape comes from pr-body-shape.sh (the repo's PR template):
#   template  ## Summary, ## Visual verification, ## Considerations, ## Agent (Repo since #4470)
#   dtf       ## Why, ## What changes, ## Visual verification, ## Scope (no such template)
#
# Exit codes:
#   0  passed, or deliberately out of scope (not the Repo repo; SignedIn gets only the
#      template-checklist check)
#   1  REFUSED — the body needs the pr-ready skill run on it
#
# Env overrides (rarely needed):
#   PR_GATE_REPO         default RepoAB/Repo
#   PR_GATE_WORD_LIMIT   default 250
#   PR_GATE_SIZE_LIMIT   default 500 (added production lines before a '- **Size:**' line is required)
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
# served elsewhere. Test guides are never posted (tester-handoff writes a local file only).
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

SIGNEDIN_REPO="RepoAB/Repo.SignedIn.Web"

check_signedin_checklist() {
  local template body item last_item last_line
  template=$(gh api "repos/$SIGNEDIN_REPO/contents/.github/pull_request_template.md" \
    -H 'Accept: application/vnd.github.raw' 2>/dev/null | tr -d '\r')
  if [ -z "$template" ]; then
    fail+=("could not read $SIGNEDIN_REPO's PR template — refusing rather than assuming")
    refuse
  fi
  body=$(gh pr view "$PR" --json body --jq .body 2>/dev/null | tr -d '\r')
  if [ -z "$body" ]; then
    fail+=("could not fetch PR #$PR body, or it is empty")
    refuse
  fi

  while IFS= read -r item; do
    [ -z "$item" ] && continue
    grep -qF -- "- [x] $item" <<<"$body" || fail+=("checklist item missing or unticked: $item")
    last_item="$item"
  done < <(sed -n 's/^- \[ \] //p' <<<"$template")
  if [ -z "${last_item:-}" ]; then
    fail+=("no checklist items found in the PR template — refusing rather than assuming")
    refuse
  fi

  grep -q '^[[:space:]]*[-*] \[ \]' <<<"$body" &&
    fail+=("unticked checkbox in the body — Task Completed Checker will fail: $(grep -m1 '^[[:space:]]*[-*] \[ \]' <<<"$body")")

  last_line=$(grep -v '^[[:space:]]*$' <<<"$body" | tail -n 1)
  [ "$last_line" = "- [x] $last_item" ] ||
    fail+=("the template checklist must be the last thing in the body (last line is: $last_line)")

  [ "${#fail[@]}" -gt 0 ] && refuse
  printf '  \033[32m✓\033[0m PR #%s body ends with the SignedIn template checklist, all ticked\n' "$PR"
  exit 0
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
# SignedIn has its own rule instead: the body must END with the repo's PR template
# checklist, every box ticked. The "Task Completed Checker" check reads every checkbox in
# the body and fails on any unticked one. Items are read from the template on the default
# branch, so a template change does not need a gate change.
if [ "$repo" = "$SIGNEDIN_REPO" ]; then
  check_signedin_checklist
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

# --- 2b. Which shape this repo expects -----------------------------------------------
shape=$(bash "$(dirname "$0")/pr-body-shape.sh" "$repo")
if [ -z "$shape" ]; then
  fail+=("could not read $repo's PR template to decide the body shape — refusing rather than assuming")
  refuse
fi

# --- 3. Strip what does not count toward the word budget -------------------------------
# Images and their markup, collapsed <details> blocks, HTML comments and fenced code, and the
# template's ## Agent section (fixed metadata, not prose to read).
# Captions are prose a human reads, so they are NOT stripped — only the markup lines.
awk '
  /^## /            { inagent = ($0 ~ /^## Agent[[:space:]]*$/) }
  inagent           { next }
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
if [ "$shape" = template ]; then
  required_headings=('## Summary' '## Agent')
  for misplaced in 'Why' 'What changes' 'Scope' 'Not in this PR' 'Risk' 'Risks'; do
    if grep -qEi "^#{1,4} +${misplaced}[[:space:]]*$" "$tmp"; then
      fail+=("section '## $misplaced' is the dtf shape — this repo's template wants it folded into ## Summary (why, what) or ## Considerations (scope, risk)")
    fi
  done
  for field in 'Process' 'Agent' 'Skills'; do
    if ! awk '/^## /{a=($0 ~ /^## Agent[[:space:]]*$/)} a' "$tmp" | grep -qE "^- \*\*${field}:\*\* *[^ ]"; then
      fail+=("## Agent is missing a filled-in '- **${field}:**' line (see the repo's PR template)")
    fi
  done
else
  required_headings=('## Why' '## What changes')
fi
for required in "${required_headings[@]}"; do
  if ! grep -qE "^${required}[[:space:]]*$" "$tmp"; then
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

# --- 8b. Size: past 500 production lines the body says why it can't split --------------
# Root AGENTS.md: "Past 500 added production lines (generated files, tests, docs and
# prototypes excluded), say in the PR body why it can't split." The exclusions are the
# pathspec /reviewing-changes measures with, so both report the same number. Counted
# locally against the PR's own base (not origin/main: stacked PRs). An uncountable diff
# refuses: this is the check most likely to be argued away.
SIZE_LIMIT="${PR_GATE_SIZE_LIMIT:-500}"
pr_refs=$(gh pr view "$PR" --json baseRefName,headRefName,headRefOid --jq '[.baseRefName,.headRefName,.headRefOid]|@tsv' 2>/dev/null)
IFS=$'\t' read -r base_ref head_ref head_oid <<<"$pr_refs"
if [ -z "${head_oid:-}" ]; then
  fail+=("could not read PR #$PR base/head to count production lines — refusing rather than assuming")
else
  git cat-file -e "$head_oid" 2>/dev/null || git fetch -q --no-tags origin "pull/$PR/head" 2>/dev/null
  git rev-parse -q --verify "origin/$base_ref" >/dev/null || git fetch -q --no-tags origin "$base_ref" 2>/dev/null
  mb=$(git merge-base "origin/$base_ref" "$head_oid" 2>/dev/null)
  if [ -z "$mb" ]; then
    # No local commits (fetch blocked, or not run from the checkout): count from the API's
    # per-file additions with the same exclusions. linguist-generated is read from the
    # local .gitattributes when there is one.
    prod_lines=$(gh api --paginate "repos/$repo/pulls/$PR/files?per_page=100" \
      --jq '.[] | [.filename, (.additions|tostring)] | @tsv' 2>/dev/null | python3 -c '
import re, subprocess, sys
rows = [l.rstrip("\n").split("\t") for l in sys.stdin if "\t" in l]
if not rows:
    sys.exit(1)
EXCL = re.compile(r"(^|/)[^/]*\.(Test|IntegrationTests)/|^shared/Repo\.Shared\.IntegrationTesting/|\.test\.tsx?$|\.spec\.ts$"
                  r"|(^|/)__tests__/|(^|/)tests/|[Ff]ixtures\.ts$|(^|/)test_[^/]*\.py$|\.md$|^apps/web/prototypes/")
gen = set()
out = subprocess.run(["git", "check-attr", "linguist-generated", "--"] + [r[0] for r in rows],
                     capture_output=True, text=True).stdout
for line in out.splitlines():
    f, _, v = line.rpartition(": linguist-generated: ")
    if v.strip() == "true":
        gen.add(f)
print(sum(int(a) for f, a in rows if f not in gen and not EXCL.search(f)))
')
    if ! printf '%s' "$prod_lines" | grep -qE '^[0-9]+$'; then
      fail+=("could not count PR #$PR production lines (no local merge-base, API read failed) — refusing rather than assuming")
      prod_lines=0
    fi
  else
    prod_lines=$(git diff --shortstat "$mb" "$head_oid" -- . ':(exclude,attr:linguist-generated=true)' \
      ':(exclude,glob)**/*.Test/**' ':(exclude,glob)**/*.IntegrationTests/**' \
      ':(exclude)shared/Repo.Shared.IntegrationTesting' ':(exclude,glob)**/*.test.ts*' \
      ':(exclude,glob)**/*.spec.ts' ':(exclude,glob)**/__tests__/**' ':(exclude,glob)**/tests/**' \
      ':(exclude,glob)**/*[Ff]ixtures.ts' ':(exclude,glob)**/test_*.py' ':(exclude,glob)**/*.md' \
      ':(exclude)apps/web/prototypes' 2>/dev/null | sed -nE 's/.* ([0-9]+) insertion.*/\1/p')
    prod_lines=${prod_lines:-0}
  fi
  if [ "$prod_lines" -gt "$SIZE_LIMIT" ] && ! grep -qE '^[-*] \*\*Size:\*\* *[^ ]' "$tmp"; then
    fail+=("$prod_lines added production lines (over $SIZE_LIMIT) and no '- **Size:** <why it can't split>' line in the body (AGENTS.md: Slice)")
  fi
fi

# --- 8b. Walkthrough for a flow (needs_walkthrough, decided at plan time) ---------------
# Run from the ticket worktree. true → the body needs `### Walkthrough` (the video, captioned).
# unset in a DTF worktree whose PR changes .tsx → refuse: the decision was never made, which is
# how a flow ships with screenshots only. Outside a DTF worktree there is nothing to read.
walkthrough=$(bash "$HOME/.claude/scripts/walkthrough-required.sh" 2>/dev/null || echo "no-dtf")
has_walkthrough_heading=0
grep -qE '^###[[:space:]]+Walkthrough[[:space:]]*$' "$tmp" && has_walkthrough_heading=1
case "$walkthrough" in
  true)
    if [ "$has_walkthrough_heading" -eq 0 ]; then
      fail+=("needs_walkthrough: true, but the body has no '### Walkthrough' under '## Visual verification' (upload walkthrough-<flow>.webm and caption it with pr-screenshot-captions)")
    fi
    ;;
  unset)
    pr_tsx=$(gh pr diff "$PR" --repo "$REPO_ALLOW" --name-only 2>/dev/null | grep -cE '\.tsx$' || true)
    if [ "${pr_tsx:-0}" -gt 0 ]; then
      fail+=("PR changes $pr_tsx .tsx file(s) but no plan file declares needs_walkthrough: true|false (.dream-team/context.md or notes/*.md). Decide it, with a one-clause reason")
    fi
    ;;
  no-dtf)
    warn+=("not run from a DTF worktree — the needs_walkthrough check was skipped")
    ;;
esac

# --- 9. Verdict ------------------------------------------------------------------------
if [ "${#fail[@]}" -gt 0 ]; then
  refuse
fi

printf '  \033[32m✓\033[0m PR #%s body (%s shape): %s words, %s production lines, no banned sections\n' "$PR" "$shape" "$words" "${prod_lines:-?}"
if [ "${#warn[@]}" -gt 0 ]; then
  for w in "${warn[@]}"; do printf '  \033[33m!\033[0m %s\n' "$w"; done
fi
exit 0
