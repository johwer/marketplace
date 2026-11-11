#!/usr/bin/env python3
"""PreToolUse guard for Write|Edit into a Claude project memory dir.

Exit 2 blocks the tool call and feeds stderr back to the model.
"""
import json
import os
import re
import sys

INDEX_BUDGET_BYTES = int(os.environ.get("MEMORY_INDEX_BUDGET", "6000"))
INDEX_LINE_MAX = int(os.environ.get("MEMORY_INDEX_LINE_MAX", "160"))
MEMORY_DIR = re.compile(r"/\.claude/projects/[^/]+/memory/")
HOME_LINE = re.compile(r"^\*\*Home:\*\*", re.MULTILINE)


def block(msg: str) -> None:
    print(msg, file=sys.stderr)
    sys.exit(2)


def resulting_text(tool: str, ti: dict, path: str) -> tuple[str, str]:
    before = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    if tool == "Write":
        return before, ti.get("content", "")
    old, new = ti.get("old_string", ""), ti.get("new_string", "")
    after = before.replace(old, new) if ti.get("replace_all") else before.replace(old, new, 1)
    return before, after


def check_index(before: str, after: str) -> None:
    grew = len(after.encode()) > len(before.encode())
    if grew and len(after.encode()) > INDEX_BUDGET_BYTES:
        block(
            f"MEMORY.md is {len(after.encode())} bytes, budget {INDEX_BUDGET_BYTES}. "
            "It may not grow while over budget. Remove or merge an entry first, "
            "or route the learning to a hook/skill/doc instead of memory."
        )
    old_long = {l for l in before.splitlines() if len(l) > INDEX_LINE_MAX}
    new_long = [l for l in after.splitlines() if len(l) > INDEX_LINE_MAX and l not in old_long]
    if new_long:
        block(
            f"MEMORY.md line over {INDEX_LINE_MAX} chars: the index holds pointers, "
            f"not content. Shorten: {new_long[0][:80]}..."
        )


def check_new_feedback(path: str, after: str) -> None:
    if os.path.exists(path) or not os.path.basename(path).startswith("feedback_"):
        return
    if not HOME_LINE.search(after):
        block(
            "New feedback memory needs a '**Home:**' line saying why this is not a "
            "hook/script, a skill or a repo doc. If it has such a home, put it there "
            "and do not write a memory."
        )


def main() -> None:
    payload = json.load(sys.stdin)
    tool = payload.get("tool_name", "")
    ti = payload.get("tool_input", {})
    path = ti.get("file_path", "")
    if tool not in ("Write", "Edit") or not MEMORY_DIR.search(path):
        return
    before, after = resulting_text(tool, ti, path)
    if os.path.basename(path) == "MEMORY.md":
        check_index(before, after)
    else:
        check_new_feedback(path, after)


if __name__ == "__main__":
    main()
