#!/usr/bin/env python3
"""PreToolUse Bash: block rebuilding the main Repo docker stack from a non-main branch."""
import json, os, re, subprocess, sys

MAIN = os.path.realpath(os.path.expanduser("~/Documents/Repo"))
BUILD = re.compile(r"\bdocker(?:\s+compose|-compose)\b[^;&|\n]*(\bup\b[^;&|\n]*--build\b|\bbuild\b)")


def main():
    p = json.load(sys.stdin)
    cmd = p.get("tool_input", {}).get("command", "")
    m = BUILD.search(cmd)
    if not m:
        return
    cwd = p.get("cwd") or "."
    cds = re.findall(r"(?:^|[;&]\s*)cd\s+(\S+)", cmd[: m.start()])
    if cds:
        cwd = os.path.join(cwd, os.path.expanduser(cds[-1]))
    f = re.search(r"\s-f\s+(\S+)", m.group(0))
    if f:
        cwd = os.path.dirname(os.path.join(cwd, os.path.expanduser(f.group(1))))
    if os.path.realpath(cwd) != MAIN:
        return
    branch = subprocess.run(["git", "-C", MAIN, "rev-parse", "--abbrev-ref", "HEAD"],
                            capture_output=True, text=True, timeout=10).stdout.strip()
    if not branch or branch == "main":
        return
    print(
        f"MAIN STACK GUARD — blocked: ~/Documents/Repo is on '{branch}', not main, and this rebuilds the shared "
        "main docker stack from branch code. Run the branch's services from its worktree on isolated ports "
        "(allocate-ports.sh, then scripts/worktree-service.sh up <service>), or leave the rebuild to the user.",
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
