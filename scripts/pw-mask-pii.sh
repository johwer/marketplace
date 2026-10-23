#!/usr/bin/env bash
# Mask national-ID-shaped text (SE personnummer / samordningsnummer, FI henkilötunnus,
# NO fødselsnummer) in the live page of a playwright-cli session, right before a screenshot.
#
# Usage: pw-mask-pii.sh <session-name>
#   then immediately: playwright-cli -s=<session-name> screenshot --filename=...
#
# Prints "masked: N" (N = number of text nodes / input values rewritten). Exit 1 if the eval
# itself failed, so a broken mask can never read as "nothing to mask".
# Re-run after EVERY navigation or re-render: React restores the real text on the next render.
set -uo pipefail

SESSION="${1:-}"
if [[ -z "$SESSION" ]]; then
  echo "usage: pw-mask-pii.sh <playwright-cli session name>" >&2
  exit 2
fi

PW=(playwright-cli)
command -v playwright-cli >/dev/null 2>&1 || PW=(npx -y @playwright/cli@0.1.22)

JS='() => {
  const re = /\b(?:\d{8}|\d{6})[-+]?\d{4}\b|\b\d{6}[-+A-FU-Y]\d{3}[0-9A-Y]\b|\b\d{11}\b/g;
  const mask = (s) => s.replace(re, (m) => m.replace(/[0-9]/g, "X"));
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
  };
  walk(document.body);
  document.querySelectorAll("iframe").forEach((f) => {
    try { if (f.contentDocument && f.contentDocument.body) walk(f.contentDocument.body); } catch (e) {}
  });
  return "masked: " + count;
}'

OUT=$("${PW[@]}" -s="$SESSION" eval "$JS" 2>&1)
RC=$?
RESULT=$(grep -o -m1 'masked: [0-9]*' <<<"$OUT" || true)
if [[ $RC -ne 0 || -z "$RESULT" ]]; then
  echo "$OUT" >&2
  echo "pw-mask-pii: mask did NOT run (rc=$RC). Do not take the screenshot." >&2
  exit 1
fi
echo "$RESULT"
