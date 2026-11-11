#!/usr/bin/env python3
"""PreToolUse Write|Edit: ask before changing apps/web/.env.local (holds the user's dev-login setup)."""
import json, sys


def main():
    p = json.load(sys.stdin)
    path = p.get("tool_input", {}).get("file_path", "")
    if not path.endswith("/apps/web/.env.local"):
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": (
            "apps/web/.env.local holds the VITE_DEV_LOGIN_* auto-login the user relies on. Only login-PAGE captures "
            "need it changed: schedule those last, use the in-app company switcher for other retailers, and remind "
            "the user to restore it afterwards."),
    }}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
