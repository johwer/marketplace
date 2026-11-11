#!/usr/bin/env python3
"""PreToolUse Bash: block a force-push that would drop commits only the remote branch has."""
import json, os, re, subprocess, sys

FORCE = re.compile(r"\bgit\s+(?:-C\s+\S+\s+)?push\b[^;&|\n]*(\s--force\b|\s--force-with-lease\b|\s-[a-zA-Z]*f\b|\s\+\S+)")


def git(cwd, *args, timeout=20):
    return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=timeout)


def main():
    p = json.load(sys.stdin)
    cmd = p.get("tool_input", {}).get("command", "")
    m = FORCE.search(cmd)
    if not m or "DTF_FORCE_PUSH_CHECKED=1" in cmd:
        return
    cwd = p.get("cwd") or "."
    c = re.search(r"\bgit\s+-C\s+(\S+)\s+push", cmd) or re.search(r"(?:^|[;&]\s*)cd\s+(\S+)\s*&&[^;]*\bgit\s+push", cmd)
    if c:
        cwd = os.path.join(cwd, os.path.expanduser(c.group(1)))
    branch = git(cwd, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    if not branch or branch == "HEAD":
        return
    if git(cwd, "fetch", "--quiet", "origin", branch).returncode != 0:
        return
    remote = f"origin/{branch}"
    if git(cwd, "rev-parse", "--verify", "--quiet", remote).returncode != 0:
        return
    excl = ["^origin/main"] if git(cwd, "rev-parse", "--verify", "--quiet", "origin/main").returncode == 0 else []
    r = git(cwd, "log", "--oneline", "--no-merges", "--right-only", "--cherry-pick", f"HEAD...{remote}", *excl)
    lost = r.stdout.strip()
    if r.returncode != 0 or not lost:
        return
    print(
        f"FORCE-PUSH GUARD — blocked: {remote} has commits with no equivalent in HEAD; this push would drop them:\n{lost}\n"
        f"Check for stacked PRs merged into this branch (gh pr list --base {branch} --state all) and cherry-pick or rebase "
        f"them in. If two branches disagree on a shared contract, settle it on who owns the contract, not on push order. "
        f"When every listed commit is accounted for, re-run with DTF_FORCE_PUSH_CHECKED=1 prefixed to the command.",
        file=sys.stderr,
    )
    sys.exit(2)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)
