#!/usr/bin/env bash
# Mask national-ID-shaped text (SE personnummer / samordningsnummer, FI henkilötunnus,
# NO fødselsnummer) AND people's names in the live page of a playwright-cli session, right
# before a screenshot.
#
# Usage: pw-mask-pii.sh <session-name> [--h1] [name ...]
#   --h1     also treat the page's <h1> text as a name (nurse/employee pages put the person there)
#   name     a full name to mask; each word of it is masked too (first name, last name)
#   then immediately: playwright-cli -s=<session-name> screenshot --filename=...
#
# Names are passed at run time only — never write them into a file or a command you commit.
# Blanking the h1 alone is not enough: the same name repeats elsewhere (the Samtalsguide on the
# nurse create form, PROJ-4761; six accept shots carried a full name, PROJ-4821). So every text
# node, input value, title and aria-label is rewritten, and the page's innerText is then checked:
# if any name is still visible the script exits 1 and the screenshot must not be taken.
#
# Prints "masked: N" (N = number of text nodes / values rewritten). Exit 1 if the eval itself
# failed or a name survived, so a broken mask can never read as "nothing to mask".
# Re-run after EVERY navigation or re-render: React restores the real text on the next render.
set -uo pipefail

SESSION="${1:-}"
if [[ -z "$SESSION" ]]; then
  echo "usage: pw-mask-pii.sh <playwright-cli session name> [--h1] [name ...]" >&2
  exit 2
fi
shift
USE_H1=false
NAMES=()
for a in "$@"; do
  if [[ "$a" == "--h1" ]]; then USE_H1=true; else NAMES+=("$a"); fi
done

PW=(playwright-cli)
command -v playwright-cli >/dev/null 2>&1 || PW=(npx -y @playwright/cli@0.1.22)

NAMES_JSON=$(printf '%s\n' "${NAMES[@]+"${NAMES[@]}"}" | python3 -I -c 'import json,sys; print(json.dumps([l for l in sys.stdin.read().split("\n") if l.strip()]))')

JS='async () => {
  const names = '"$NAMES_JSON"';
  if ('"$USE_H1"') {
    const h1 = document.querySelector("h1");
    if (h1 && h1.innerText.trim()) names.push(h1.innerText.trim());
  }
  const words = new Set();
  for (const n of names) {
    words.add(n);
    for (const w of n.split(/\s+/)) if (w.length >= 2) words.add(w);
  }
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const sorted = [...words].sort((a, b) => b.length - a.length);
  const nameRe = sorted.length ? new RegExp(sorted.map(esc).join("|"), "gi") : null;
  const re = /\b(?:\d{8}|\d{6})[-+]?\d{4}\b|\b\d{6}[-+A-FU-Y]\d{3}[0-9A-Y]\b|\b\d{11}\b/g;
  const mask = (s) => {
    let out = s.replace(re, (m) => m.replace(/[0-9]/g, "X"));
    if (nameRe) out = out.replace(nameRe, "Namn");
    return out;
  };
  let count = 0;
  const walk = (root) => {
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = w.nextNode())) {
      const next = mask(n.nodeValue);
      if (next !== n.nodeValue) { n.nodeValue = next; count++; }
    }
    root.querySelectorAll("input, textarea").forEach((el) => {
      const next = mask(el.value);
      if (next !== el.value) { el.value = next; count++; }
    });
    root.querySelectorAll("[title], [aria-label], [placeholder]").forEach((el) => {
      for (const a of ["title", "aria-label", "placeholder"]) {
        const v = el.getAttribute(a);
        if (v !== null && mask(v) !== v) { el.setAttribute(a, mask(v)); count++; }
      }
    });
    root.querySelectorAll("*").forEach((el) => { if (el.shadowRoot) { roots.push(el.shadowRoot); walk(el.shadowRoot); } });
  };
  const roots = [document.body];
  document.querySelectorAll("iframe").forEach((f) => {
    try { if (f.contentDocument && f.contentDocument.body) roots.push(f.contentDocument.body); } catch (e) {}
  });
  roots.forEach(walk);
  if (nameRe) {
    await new Promise((r) => setTimeout(r, 300));
    const visible = roots.map((r) => (r.innerText ?? r.textContent) + " " +
      [...r.querySelectorAll("input, textarea")].map((e) => e.value).join(" ")).join(" ");
    nameRe.lastIndex = 0;
    if (nameRe.test(visible)) return "NAME STILL VISIBLE";
  }
  return "masked: " + count;
}'

OUT=$("${PW[@]}" -s="$SESSION" eval "$JS" 2>&1)
RC=$?
# playwright-cli echoes the evaluated code too, so read only the "### Result" section.
RESULT_SECTION=$(awk '/^### Result/{f=1;next} /^### /{f=0} f' <<<"$OUT")
if grep -q 'NAME STILL VISIBLE' <<<"$RESULT_SECTION"; then
  echo "pw-mask-pii: a name is still visible after masking. Do NOT take the screenshot." >&2
  exit 1
fi
RESULT=$(grep -o -m1 'masked: [0-9]*' <<<"$RESULT_SECTION" || true)
if [[ $RC -ne 0 || -z "$RESULT" ]]; then
  echo "$OUT" >&2
  echo "pw-mask-pii: mask did NOT run (rc=$RC). Do not take the screenshot." >&2
  exit 1
fi
echo "$RESULT"
