#!/usr/bin/env python3
"""retro-pr-gate.py — fail-closed level check on a retro PR that touches shared repo knowledge.

Repo DTF only. A retro PR may put a learning in shared files (docs/, AGENTS.md, CLAUDE.md,
.claude/skills/, .claude/rules/) only when its level under /retro-proposals STEP 0b is 1 or 2.
Each learning in the PR body carries one tag line:

  - <the rule, in one line> [L1 · found-by: human-review · cost: 2 h · if-missed: prod-error · scope: stack · evidence: https://github.com/.../pull/123#discussion_r1]

Rules (all checked, every violation listed):
  - at least one tag when a shared path changes
  - no L3 or Drop tag: those belong in personal config or nowhere
  - L1: scope repo|stack, and either found-by prod|human-review with evidence
        (a URL, #PR or JIRA-123), or if-missed data-loss|security|prod-error
  - L2: scope is a module (not repo/stack/ticket), and recurred >= 2 or cost >= 1 h
  - docs/ or a root CLAUDE.md needs at least one L1: level 2 lives in a module's AGENTS.md
    or a repo skill

Usage:
  retro-pr-gate.py <PR_NUMBER>                     check an open PR
  retro-pr-gate.py --body-file F --files A B ...   check a body and changed paths offline
  retro-pr-gate.py --hook                          PreToolUse Bash hook (reads JSON on stdin)
  retro-pr-gate.py --help

Exit: 0 pass or out of scope · 1 REFUSED (CLI) · 2 blocked (hook)
"""
import json, re, subprocess, sys

REPO = "RepoAB/Repo"
SHARED = re.compile(r"^(docs/|\.claude/(skills|rules)/)|(^|/)(AGENTS|CLAUDE)\.md$")
L1_ONLY = re.compile(r"^docs/|^CLAUDE\.md$")
TAG = re.compile(r"\[(L1|L2|L3|Drop)\b([^\]]*)\]", re.I)
EVIDENCE = re.compile(r"https?://\S+|#\d+|\b[A-Z][A-Z0-9]+-\d+\b")
RETRO = re.compile(r"retro", re.I)


def fields(raw):
    out = {}
    for part in re.split(r"[·|;]", raw):
        if ":" in part:
            k, v = part.split(":", 1)
            out[k.strip().lower()] = v.strip().lower()
    return out


def hours(cost):
    m = re.search(r"(\d+(?:\.\d+)?)\s*(h|hour|min|m)\b", cost or "")
    if not m:
        return 0.0
    n = float(m.group(1))
    return n if m.group(2).startswith("h") else n / 60


def check(body, files):
    shared = [f for f in files if SHARED.search(f)]
    if not shared:
        return []
    fails = []
    tags = [(m.group(1).upper(), fields(m.group(2)), m.group(0)) for m in TAG.finditer(body)]
    if not tags:
        fails.append(f"shared files changed ({', '.join(shared)}) but the body has no level tag. "
                     "Add one '[L1 · found-by: … · cost: … · if-missed: … · scope: … · evidence: …]' line per learning.")
    for level, f, raw in tags:
        scope, found, missed = f.get("scope", ""), f.get("found-by", ""), f.get("if-missed", "")
        if level in ("L3", "DROP"):
            fails.append(f"{raw}: level 3 and Drop never go in shared files; move it to personal config or strike it.")
        elif level == "L1":
            if scope not in ("repo", "stack"):
                fails.append(f"{raw}: L1 needs scope repo or stack.")
            human = found in ("prod", "human-review") and EVIDENCE.search(f.get("evidence", ""))
            severe = missed in ("data-loss", "security", "prod-error")
            if not (human or severe):
                fails.append(f"{raw}: L1 needs found-by prod|human-review with evidence, or if-missed data-loss|security|prod-error.")
        elif level == "L2":
            if scope in ("", "repo", "stack", "ticket"):
                fails.append(f"{raw}: L2 needs scope set to one module.")
            rec = re.search(r"\d+", f.get("recurred", ""))
            if not ((rec and int(rec.group()) >= 2) or hours(f.get("cost")) >= 1):
                fails.append(f"{raw}: L2 needs recurred >= 2 or cost >= 1 h.")
    l1_files = [f for f in shared if L1_ONLY.search(f)]
    if l1_files and not any(t[0] == "L1" for t in tags):
        fails.append(f"{', '.join(l1_files)} take level 1 only; level 2 belongs in a module's AGENTS.md or a repo skill.")
    return fails


def gh_pr(pr):
    r = subprocess.run(["gh", "pr", "view", str(pr), "-R", REPO, "--json", "body,files,headRefName,title"],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return json.loads(r.stdout)


def report(fails, where):
    if not fails:
        print(f"✓ retro level gate passed: {where}")
        return 0
    print(f"✗ RETRO LEVEL GATE — refused: {where}", file=sys.stderr)
    for f in fails:
        print(f"  - {f}", file=sys.stderr)
    print("  Grade each learning under /retro-proposals STEP 0b. Level 3 goes to ~/.claude, not the repo.", file=sys.stderr)
    return 1


def hook():
    p = json.load(sys.stdin)
    cmd = p.get("tool_input", {}).get("command", "")
    cwd = p.get("cwd") or "."
    if re.search(r"\bgh\s+pr\s+create\b", cmd):
        branch = subprocess.run(["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
                                capture_output=True, text=True).stdout.strip()
        if (RETRO.search(branch) or RETRO.search(cmd)) and "--draft" not in cmd:
            print("RETRO LEVEL GATE — blocked: create a retro PR as --draft, then run "
                  "python3 ~/.claude/scripts/retro-pr-gate.py <PR> before it goes ready.", file=sys.stderr)
            sys.exit(2)
        return
    m = re.search(r"\bgh\s+pr\s+ready\s+(\d+)", cmd)
    if not m:
        return
    pr = gh_pr(m.group(1))
    if not (RETRO.search(pr["headRefName"]) or RETRO.search(pr["title"])):
        return
    if report(check(pr["body"] or "", [f["path"] for f in pr["files"]]), f"PR #{m.group(1)}"):
        sys.exit(2)


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "--hook":
        try:
            hook()
        except SystemExit:
            raise
        except Exception:
            return 0
        return 0
    if argv[0] == "--body-file":
        body = open(argv[1]).read()
        files = argv[argv.index("--files") + 1:]
        return report(check(body, files), argv[1])
    pr = gh_pr(argv[0])
    if not (RETRO.search(pr["headRefName"]) or RETRO.search(pr["title"])):
        print(f"✓ retro level gate: PR #{argv[0]} is not a retro PR, out of scope")
        return 0
    return report(check(pr["body"] or "", [f["path"] for f in pr["files"]]), f"PR #{argv[0]}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
