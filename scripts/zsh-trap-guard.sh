#!/bin/bash
# PreToolUse hook (matcher: Bash) — refuses the zsh traps that kept recurring in DTF sessions
# despite the written Verification Discipline rule (PROJ-4584, PROJ-4622, PROJ-4472, PROJ-4647).
# The Bash tool runs the user's login shell (zsh), where these behave differently from bash and
# fail silently or with a misleading error.
#
# Deliberately narrow — only these three shapes are refused:
#   1. `echo ===...` / `printf ==...`   unquoted leading `=` is zsh =-expansion ("= not found")
#   2. `${VAR:+word with spaces}`       zsh passes the alternative as ONE argument
#   3. `NAME="cmd args"; $NAME ...`     zsh does not word-split a scalar at command position
# Commands already handed to bash (`bash -c`, `bash <<`, `bash script.sh`) are allowed through.
#
# Exit 0 = allow, exit 2 = block (stderr goes back to Claude).

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$CMD" ] && exit 0

REASON=$(CMD="$CMD" python3 -I - <<'PY'
import os, re
cmd = os.environ["CMD"]

# Already running under bash: the traps do not apply.
if re.search(r'(^|[\s;&|(])(/bin/)?bash\s+(-[a-z]*c\b|<<|-s\b|\S+\.sh\b)', cmd):
    raise SystemExit(0)

# Drop single-quoted strings so quoted text (e.g. commit messages, jq/awk programs) never matches.
unq = re.sub(r"'[^']*'", "''", cmd)

# 1. echo/printf with an unquoted word starting with '='
if re.search(r'(^|[\s;&|(])(echo|printf)(\s+-\w+)*\s+=', unq):
    print("zsh =-expansion: an unquoted word starting with '=' after echo/printf fails "
          "('= not found'). Quote it (echo '=====') or run the command in bash -c '...'.")
    raise SystemExit(0)

# 2. ${VAR:+...} whose alternative contains whitespace, outside double quotes
for m in re.finditer(r'\$\{\w+:\+([^}]*)\}', unq):
    before = unq[:m.start()]
    in_dq = before.count('"') % 2 == 1
    if not in_dq and re.search(r'\s', m.group(1)):
        print("zsh does not word-split ${VAR:+...}: the alternative reaches the command as ONE "
              "argument. Run this command in bash -c '...' (or a scratchpad .sh run with bash).")
        raise SystemExit(0)

# 3. NAME="multi word" (or 'multi word') later used as $NAME at command position
names = set(re.findall(r'(?:^|[\s;&|(])([A-Za-z_]\w*)="[^"]*\s[^"]*"', unq))
names |= set(re.findall(r"(?:^|[\s;&|(])([A-Za-z_]\w*)='[^']*\s[^']*'", cmd))
for n in names:
    if re.search(r'(^|[;&|(]|\n|&&|\|\|)\s*\$\{?' + re.escape(n) + r'\}?(\s|$)', unq):
        print(f"zsh does not word-split the scalar ${n}: '${n} args' runs a command literally named "
              f"after the whole string, and a redirected error reads as empty output. Use an array, "
              f"a function, or run it in bash -c '...'.")
        raise SystemExit(0)
PY
)

if [ -n "$REASON" ]; then
  echo "ZSH TRAP GUARD — blocked: $REASON" >&2
  exit 2
fi
exit 0
