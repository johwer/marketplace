#!/usr/bin/env bash
# comment-gate.sh — deterministic, fail-closed check on comments ADDED by a change.
#
# The rule it enforces is AGENTS.md#comments: comments are a smell. The only exceptions are
# XML `///` on endpoints and their DTOs (OpenAPI), tooling directives, `// Arrange/Act/Assert`
# in tests, and an external gotcha the code can't state. JSDoc/TSDoc, `@deprecated`, TODOs and
# `///` on other members are deliberately NOT exceptions. In C#, analyzer MH0001 also fails
# the build on comments in member bodies; this gate covers TS/JS and the C# outside bodies.
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
#   0  nothing refused (a REVIEW list may still be printed — those want a human judgement)
#   1  REFUSED — an added comment carries a ticket number, is a JSDoc/TSDoc block in TS/JS,
#      or restates the code on the line below it
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
# Diff BASE against the WORKING TREE, not HEAD, and append untracked files: a new file's
# header JSDoc used to pass the first run and fail only after `git add` + commit (PROJ-4491).
PATTERNS=('*.ts' '*.tsx' '*.cs' '*.mts' '*.js' '*.mjs')
DIFF=$(git diff "$BASE" -U0 -- "${PATTERNS[@]}" 2>/dev/null)
while IFS= read -r -d '' f; do
  DIFF+=$'\n'"$(git diff --no-index -U0 -- /dev/null "$f" 2>/dev/null)"
done < <(git ls-files -z --others --exclude-standard -- "${PATTERNS[@]}" 2>/dev/null)
DIFF=$(printf '%s' "$DIFF" | sed -E '/^[[:space:]]*$/d')
if [ -z "$DIFF" ]; then
  printf '  \033[32m✓\033[0m comment-gate: no source changes to check\n'
  exit 0
fi

printf '%s' "$DIFF" | OVERLAP="$OVERLAP" STRICT="$STRICT" python3 -c '
import os, re, sys

OVERLAP = float(os.environ["OVERLAP"])
STRICT  = os.environ["STRICT"] == "1"

# AGENTS.md#comments exceptions. Only tooling directives and the test-phase markers are
# allowed outright; TODO(, NOSONAR and #region were allowed before and are not any more.
# The ReSharper/language= prefixes mirror the tooling list in MH0001.
ALLOW = re.compile(r"eslint-disable|eslint-enable|@ts-|prettier-ignore|#pragma|csharpier-ignore|//\s*(ReSharper |language=|lang=)")
AAA = re.compile(r"^\s*//\s*(Arrange|Act|Assert)(\s*(&|and|/)\s*(Act|Assert))?\s*:?\s*$")
XMLDOC = re.compile(r"^\s*///")
JSDOC_START = re.compile(r"^\s*/\*\*")
DOC_CONT = re.compile(r"^\s*(\*\s|\*$|\*/)")
DOC = re.compile(r"^\s*(///|/\*\*|\*\s|\*$|\*/)")
# XML docs are the OpenAPI exception, which applies to endpoints and their DTOs only. A path
# is the cheapest deterministic proxy; anything else lands on the REVIEW list.
API_PATH = re.compile(r"(Controller|Dto|Request|Response|Contract|Model)s?(/|\.cs$)|/(Controllers|Dtos?|Contracts|Models|Requests|Responses)/")
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

# Generated clients (linguist-generated in .gitattributes) carry the backend XML docs as
# JSDoc and are regenerated, never hand-edited. Prototypes are a sandbox on fake data,
# shipped to accept only. Neither is held to the comment rule.
import subprocess
paths = sorted({q for q, _, _ in added if q})
generated = set()
if paths:
    out = subprocess.run(["git", "check-attr", "linguist-generated", "--"] + paths,
                         capture_output=True, text=True).stdout
    for row in out.splitlines():
        f, _, val = row.rpartition(": linguist-generated: ")
        if val.strip() == "true":
            generated.add(f)
SKIP = re.compile(r"(^|/)apps/web/prototypes/")
skipped = {q for q in paths if q in generated or SKIP.search(q)}
added = [row for row in added if row[0] not in skipped]
if skipped:
    sys.stdout.write("  comment-gate: skipped %d generated/prototype file(s)\n" % len(skipped))

TICKET = re.compile(r"\b(?:NOVA|PLRS)-\d+\b")
COMMENTISH = re.compile(r"^\s*(//|/\*|\*)")
TSJS = re.compile(r"\.(ts|tsx|mts|js|mjs)$")

PRAGMA_OFF = re.compile(r"#pragma\s+warning\s+disable\b.*\bMH0001\b")
PRAGMA_ON = re.compile(r"#pragma\s+warning\s+restore\b.*\bMH0001\b")

restating, review, ticketed, jsdoc = [], [], [], []
suppressed = set()
for i, (p, n, text) in enumerate(added):
    # A gotcha wrapped in #pragma warning disable MH0001 is the sanctioned C# form.
    if PRAGMA_OFF.search(text):
        suppressed.add(p); continue
    if PRAGMA_ON.search(text):
        suppressed.discard(p); continue
    # A ticket number is banned in ANY comment, TSDoc and XML docs included. AGENTS.md no
    # longer says so explicitly; DTF keeps the ban (PROJ-4179): it belongs in the PR/commit.
    if COMMENTISH.match(text) and TICKET.search(text) and not ALLOW.search(text):
        ticketed.append((p, n, text.strip()[:78], 1.0))
        continue
    if ALLOW.search(text) or AAA.match(text) or p in suppressed:
        continue
    if JSDOC_START.match(text):
        # TS/JS has no OpenAPI exception, so a doc block there is never one of the
        # allowed kinds. Elsewhere (a C# /** */) it wants a judgement.
        shown = text.strip()
        if shown == "/**" and i + 1 < len(added) and added[i+1][0] == p:
            shown += " " + added[i+1][2].strip()
        (jsdoc if TSJS.search(p or "") else review).append((p, n, shown[:78], 1.0))
        continue
    if XMLDOC.match(text):
        prev_xml = i > 0 and added[i-1][0] == p and added[i-1][1] == n - 1 and XMLDOC.match(added[i-1][2])
        if not prev_xml and not API_PATH.search(p or ""):
            review.append((p, n, text.strip()[:78] + "  [/// outside an endpoint/DTO file]", 0.0))
        continue
    if DOC_CONT.match(text):
        continue
    m = LINE_COMMENT.match(text) or BLOCK_ONELINE.match(text)
    if not m:
        continue
    # A column-0 comment (file header, section divider) used to be exempt (PROJ-4185).
    # AGENTS.md has no such exception, so it is listed for judgement, never auto-refused.
    if not text[:1].isspace():
        review.append((p, n, m.group(1).strip()[:78], 0.0))
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

if ticketed:
    sys.stdout.write("\n  \033[31mREFUSED\033[0m — %d added comment(s) carry a ticket number"
                     " (put it in the PR or commit message)\n\n" % len(ticketed))
    show(ticketed, "x", "31")
if jsdoc:
    sys.stdout.write("\n  \033[31mREFUSED\033[0m — %d added JSDoc/TSDoc block(s) in TS/JS"
                     " (AGENTS.md#comments: not an allowed exception; use names and types)\n\n" % len(jsdoc))
    show(jsdoc, "x", "31")
if restating:
    sys.stdout.write("\n  \033[31mREFUSED\033[0m — %d added comment(s) restate the code below them\n"
                     "  (AGENTS.md#comments — comments are a smell; prefer names, small functions, types)\n\n" % len(restating))
    show(restating, "x", "31")
if review:
    sys.stdout.write("\n  \033[33m!\033[0m %d other added comment(s) — keep one only if it is an external gotcha"
                     " the code cannot state (AGENTS.md#comments); in C# wrap it in #pragma warning disable MH0001:\n\n" % len(review))
    show(review, "?", "33")

if ticketed or jsdoc or restating or (STRICT and review):
    sys.stdout.write("\n  Delete every line listed above in ONE pass, then re-run this gate.\n\n")
    sys.exit(1)

if not review:
    sys.stdout.write("  \033[32m✓\033[0m comment-gate: no comments added\n")
else:
    sys.stdout.write("\n  \033[32m✓\033[0m comment-gate: none restating (%d flagged for judgement above)\n" % len(review))
sys.exit(0)
'
