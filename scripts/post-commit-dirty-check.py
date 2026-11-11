#!/usr/bin/env python3
"""PostToolUse Bash: after git commit, warn when tracked files are still modified (HEAD may not hold the edit)."""
import json, os, re, subprocess, sys


def main():
    p = json.load(sys.stdin)
    cmd = p.get("tool_input", {}).get("command", "")
    if not re.search(r"\bgit\s+(?:-C\s+\S+\s+)?commit\b", cmd):
        return
    c = re.search(r"\bgit\s+-C\s+(\S+)\s+commit", cmd)
    cwd = os.path.expanduser(c.group(1)) if c else (p.get("cwd") or ".")
    st = subprocess.run(["git", "-C", cwd, "status", "--porcelain", "--untracked-files=no"],
                        capture_output=True, text=True, timeout=10)
    dirty = st.stdout.strip()
    if st.returncode != 0 or not dirty:
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            "After this commit, tracked files are still modified or staged:\n" + dirty[:800] + "\n"
            "Working-tree checks do not see what HEAD holds. Confirm the commit has your change "
            "(git show HEAD --stat, git grep <pat> HEAD -- <path>) and commit or account for the rest."),
    }}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
