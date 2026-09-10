#!/usr/bin/env bash
# comment-gate.sh — deterministic, fail-closed check on comments ADDED by a change.
#
# The rule it enforces is docs/CODING_STYLE_FRONTEND.md:256 (PROJ-3283): a comment earns
# its place only when it says something the code cannot. Restating comments must go.
#
# WHY A SCRIPT: judging "why vs what" is a model's job, but ENUMERATING every added comment
# is not — and that is where the partial passes came from. A model asked to "remove the
# comments" removes the ones it happens to look at. This lists all of them, once, with
# file:line, so the fix is a single pass instead of four.
#
# Usage:  bash ~/.claude/scripts/comment-gate.sh [BASE_REF] [-- PATH...]
#         BASE_REF defaults to the merge-base with origin/main (falls back to HEAD~1).
#
# Exit codes:
#   0  no high-confidence restating comment survived (a REVIEW list may still be printed)
#   1  REFUSED — at least one added comment restates the code on the line below it
#
# Env overrides:
#   COMMENT_GATE_OVERLAP   default 0.60  — token overlap at which a comment counts as restating
#   COMMENT_GATE_STRICT    set to 1 to also refuse on the REVIEW list (nothing may be added)
#
# NOTE ON `set -e`: deliberately not used. Every file must be scanned so the operator sees
# the complete list in one pass — that completeness IS the point of this gate.
set -uo pipefail

OVERLAP="${COMMENT_GATE_OVERLAP:-0.6}"
STRICT="${COMMENT_GATE_STRICT:-0}"

BASE="${1:-}"
if [ -n "$BASE" ] && [ "$BASE" = "--" ]; then BASE=""; else shift 2>/dev/null || true; fi
if [ -z "$BASE" ]; then
  BASE=$(git merge-base origin/main HEAD 2>/dev/null) || BASE=""
  [ -z "$BASE" ] && BASE=$(git rev-parse HEAD~1 2>/dev/null)
fi
if [ -z "$BASE" ]; then
  printf '  \033[33m!\033[0m comment-gate: no base ref to diff against — skipped\n'
  exit 0
fi

# Added lines only, with real file:line numbers, for source files we have a comment rule for.
DIFF=$(git diff "$BASE"...HEAD -U0 -- '*.ts' '*.tsx' '*.cs' '*.mts' '*.js' '*.mjs' 2>/dev/null)
if [ -z "$DIFF" ]; then
  printf '  \033[32m✓\033[0m comment-gate: no source changes to check\n'
  exit 0
fi

printf '%s' "$DIFF" | OVERLAP="$OVERLAP" STRICT="$STRICT" python3 -c '
import os, re, sys

OVERLAP = float(os.environ["OVERLAP"])
STRICT  = os.environ["STRICT"] == "1"

# Declaration-level documentation is the sanctioned kind and is never flagged:
# C# XML docs, JSDoc/TSDoc blocks, and lint suppressions carrying their justification.
DOC = re.compile(r"^\s*(///|/\*\*|\*\s|\*/)")
ALLOW = re.compile(r"eslint-disable|eslint-enable|@ts-|prettier-ignore|TODO\(|NOSONAR|#pragma|#region|#endregion|csharpier-ignore")
LINE_COMMENT = re.compile(r"^\s*//(?!/)\s*(.+?)\s*$")
BLOCK_ONELINE = re.compile(r"^\s*/\*(?!\*)\s*(.+?)\s*\*/\s*$")

def tokens(s):
    # Split identifiers into words: setLoading -> {set, loading}; snake/kebab too.
    parts = re.findall(r"[A-Za-z][a-z0-9]*|[A-Z]{2,}", s)
    return {p.lower() for p in parts if len(p) > 1}

STOP = {"the","a","an","this","that","to","of","is","are","we","it","for","and","in","on","then","now","with","as","by","its","be"}

added = []          # (path, lineno, text)
path, lineno = None, 0
for raw in sys.stdin.read().splitlines():
    if raw.startswith("+++ b/"):
        path = raw[6:]; continue
    m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)", raw)
    if m:
        lineno = int(m.group(1)); continue
    if raw.startswith("+") and not raw.startswith("+++"):
        added.append((path, lineno, raw[1:]))
        lineno += 1

restating, review = [], []
for i, (p, n, text) in enumerate(added):
    if DOC.match(text) or ALLOW.search(text):
        continue
    m = LINE_COMMENT.match(text) or BLOCK_ONELINE.match(text)
    if not m:
        continue
    if i > 0:
        pp, pn, ptext = added[i-1]
        if pp == p and pn == n - 1 and (LINE_COMMENT.match(ptext) or BLOCK_ONELINE.match(ptext) or DOC.match(ptext)):
            continue
    body = m.group(1)
    ct = tokens(body) - STOP
    if not ct:
        continue
    # The code this comment sits above, within the same added block.
    nxt = ""
    for q, ln, t in added[i+1:i+3]:
        if q == p and t.strip() and not LINE_COMMENT.match(t) and not DOC.match(t):
            nxt = t; break
    score = len(ct & tokens(nxt)) / len(ct) if nxt else 0.0
    entry = (p, n, body.strip()[:78], round(score, 2))
    (restating if score >= OVERLAP else review).append(entry)

def show(rows, mark, colour):
    for p, n, body, s in rows:
        sys.stdout.write("  \033[%sm%s\033[0m %s:%d  // %s\n" % (colour, mark, p, n, body))

if restating:
    sys.stdout.write("\n  \033[31mREFUSED\033[0m — %d added comment(s) restate the code below them\n"
                     "  (docs/CODING_STYLE_FRONTEND.md:256 — a comment must say what the code cannot)\n\n" % len(restating))
    show(restating, "x", "31")
if review:
    sys.stdout.write("\n  \033[33m!\033[0m %d other added comment(s) — keep only the non-obvious WHY:\n\n" % len(review))
    show(review, "?", "33")

if restating or (STRICT and review):
    sys.stdout.write("\n  Delete every line listed above in ONE pass, then re-run this gate.\n\n")
    sys.exit(1)

if not review:
    sys.stdout.write("  \033[32m✓\033[0m comment-gate: no comments added\n")
else:
    sys.stdout.write("\n  \033[32m✓\033[0m comment-gate: none restating (%d flagged for judgement above)\n" % len(review))
sys.exit(0)
'
