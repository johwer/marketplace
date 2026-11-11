#!/usr/bin/env python3
"""PreToolUse Bash: block running a shell script with --help/-h when the script does not parse that flag."""
import json, os, re, sys

RUN = re.compile(r"(?:^|[;&|(]\s*|\b(?:bash|sh|zsh)\s+)(?P<script>[~./\w-]*[\w-]+\.sh)\b(?P<args>[^;&|\n]*)")
HELP_ARG = re.compile(r"(?:^|\s)(--help|-h)(?=\s|$)")
HELP_CASE = re.compile(r"--help|(^|[\s|(\"'])-h\)|-h\|")


def main():
    p = json.load(sys.stdin)
    cmd = p.get("tool_input", {}).get("command", "")
    cwd = p.get("cwd") or "."
    for m in RUN.finditer(cmd):
        if not HELP_ARG.search(m.group("args")):
            continue
        path = os.path.join(cwd, os.path.expanduser(m.group("script")))
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as fh:
            if HELP_CASE.search(fh.read()):
                continue
        print(
            f"SCRIPT HELP GUARD — blocked: {m.group('script')} does not parse --help/-h, so this runs it for real. "
            f"Read its usage instead: sed -n 1,40p {m.group('script')} (or grep for its argument parsing).",
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
