#!/bin/bash
# PreToolUse hook (matcher: Bash) — refuses the zsh traps that kept recurring in DTF sessions
# despite the written Verification Discipline rule (PROJ-4584, PROJ-4622, PROJ-4472, PROJ-4647).
# The Bash tool runs the user's login shell (zsh), where these behave differently from bash and
# fail silently or with a misleading error.
#
# Deliberately narrow — only these shapes are refused:
#   1. `echo ===...` / `printf ==...`   unquoted leading `=` is zsh =-expansion ("= not found")
#   2. `${VAR:+word with spaces}`       zsh passes the alternative as ONE argument
#   3. `NAME="cmd args"; $NAME ...`     zsh does not word-split a scalar at command position
#   4. `for path in ...`                zsh ties path/cdpath/fpath/manpath to $PATH etc. (PROJ-4821)
#   5. `<gating cmd> | tail ... &&`     the pipe's status is tail's, so && runs after a failure;
#      also any gating pipe into tail/head in a run_in_background call (PROJ-4014, PROJ-4750)
#   6. `git push ...; git update-ref`   the ref moves even when the push never happened (PROJ-4749)
# Rules 4-6 apply under bash too (5 and 6 are shell-independent), so they run before the bash check.
# Commands already handed to bash (`bash -c`, `bash <<`, `bash script.sh`) are allowed through,
# and heredoc bodies are ignored.
#
# Exit 0 = allow, exit 2 = block (stderr goes back to Claude).

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$CMD" ] && exit 0

BG=$(printf '%s' "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)

REASON=$(CMD="$CMD" BG="$BG" python3 -I - <<'PY'
import os, re
cmd = os.environ["CMD"]
bg = os.environ.get("BG") == "true"

# Drop heredoc bodies: they are data (a PR body, a script written to a file), not commands zsh runs.
def strip_heredocs(text):
    out, delims = [], []
    for line in text.split("\n"):
        if delims:
            if line.strip() == delims[0]:
                delims.pop(0)
            continue
        out.append(line)
        delims = [m.group(2) for m in re.finditer(r"<<(?!<)-?\s*(['\"]?)(\w+)\1", line)]
    return "\n".join(out)

cmd = strip_heredocs(cmd)

GATING = (r'(git\s+(rebase|push|pull|merge|commit|fetch|cherry-pick)\b|bash\s+\S+\.sh\b|\S*quality-gate\.sh\b'
          r'|dotnet\s+(build|test|restore|ef)\b|npm\s+(ci|test|run)\b|npx\s+(tsc|vitest|playwright|prettier|eslint)\b)')
plain = re.sub(r"'[^']*'", "''", cmd)

# 4. zsh tied arrays as loop variables
if not re.search(r'(^|[\s;&|(])(/bin/)?bash\s', cmd) and re.search(r'(^|[\s;&|(])for\s+(path|cdpath|fpath|manpath|module_path|PATH)\s+in\b', plain):
    print("zsh ties `path` (and cdpath/fpath/manpath) to $PATH: `for path in ...` rebinds PATH and every "
          "later command is 'not found'. Use another loop variable (for p in ...).")
    raise SystemExit(0)

# 5. a gating command piped into tail/head: the pipeline's status is tail's
if 'pipefail' not in cmd and 'PIPESTATUS' not in cmd:
    pipe = re.compile(GATING + r'[^|;&\n]*(2>&1\s*)?\|\s*(tail|head)\b[^;&|\n]*')
    for m in pipe.finditer(plain):
        rest = plain[m.end():]
        if bg or re.match(r'\s*(&&|\|\|)', rest):
            print("the exit status of `<gating cmd> | " + m.group(m.lastindex) + "` is " + m.group(m.lastindex) + "'s, so a failed "
                  + m.group(1).split()[0] + " looks like success" + (" to the background-task notifier" if bg else " and the && runs anyway")
                  + ". Write the output to a file and check the command's own exit: `cmd > /tmp/x.log 2>&1; rc=$?; tail -5 /tmp/x.log; [ $rc -eq 0 ] && ...` (or set -o pipefail).")
            raise SystemExit(0)

# 6. update-ref after a push separated by ';'
if re.search(r'git\s+push\b[^&|;\n]*;\s*git\s+update-ref\b', plain):
    print("`git push ...; git update-ref` moves the remote-tracking ref even when the push failed, and the next "
          "--force-with-lease leases against a wrong ref. Use `git push ... && git update-ref ...`.")
    raise SystemExit(0)

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
