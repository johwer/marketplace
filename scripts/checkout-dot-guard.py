#!/usr/bin/env python3
"""PreToolUse Bash: block whole-tree checkout/restore while the worktree has uncommitted changes."""
import json, os, re, subprocess, sys

PATTERNS = [
    re.compile(r"\bgit\s+(?:-C\s+(?P<c1>\S+)\s+)?checkout\b(?:\s+[^\s;&|-]\S*)?\s+--\s+\.(?=\s|$|[;&|])"),
    re.compile(r"\bgit\s+(?:-C\s+(?P<c2>\S+)\s+)?restore\b[^;&|\n]*--source[= ]\S+[^;&|\n]*\s\.(?=\s|$|[;&|])"),
]


def main():
    p = json.load(sys.stdin)
    cmd = p.get("tool_input", {}).get("command", "")
    for pat in PATTERNS:
        m = pat.search(cmd)
        if m:
            break
    else:
        return
    cwd = os.path.expanduser(m.groupdict().get("c1") or m.groupdict().get("c2") or p.get("cwd") or ".")
    cd = re.search(r"(?:^|[;&]\s*)cd\s+(\S+)\s*&&", cmd[: m.start()])
    if cd and not (m.groupdict().get("c1") or m.groupdict().get("c2")):
        cwd = os.path.join(p.get("cwd") or ".", os.path.expanduser(cd.group(1)))
    st = subprocess.run(["git", "-C", cwd, "status", "--porcelain"], capture_output=True, text=True, timeout=10)
    if st.returncode != 0 or not st.stdout.strip():
        return
    print(
        "CHECKOUT GUARD — blocked: this overwrites the whole working tree, and it has uncommitted changes "
        f"(possibly another agent's):\n{st.stdout.strip()[:800]}\n"
        "To inspect a ref use `git show <ref>:<path>`, `git grep <pat> <ref>` or `git diff <ref> -- <path>`. "
        "To restore specific files, name the paths instead of `.`.",
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
