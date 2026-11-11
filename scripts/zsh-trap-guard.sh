#!/bin/bash
# PreToolUse Bash wrapper for zsh-trap-guard.py; only its exit 2 blocks, anything else fails open.
python3 -I "$(dirname "$0")/zsh-trap-guard.py"
[ $? -eq 2 ] && exit 2
exit 0
