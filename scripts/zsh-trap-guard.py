#!/usr/bin/env python3
"""PreToolUse Bash: refuse zsh and shell traps that fail silently. Exit 2 blocks; internal errors fail open."""
import contextlib, io, json, re, sys


def check(cmd, bg):

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

    # 7. unquoted heredoc whose body holds a command substitution: the shell runs it before the reader sees it
    BACKTICK, DOLLAR_PAREN = chr(96), "$" + chr(40)
    def unquoted_heredoc_with_subst(text):
        lines = text.split("\n")
        for i, line in enumerate(lines):
            for m in re.finditer(r"<<(?!<)-?\s*(['\"]?)(\w+)\1", line):
                if m.group(1):
                    continue
                body = []
                for l in lines[i + 1:]:
                    if l.strip() == m.group(2):
                        break
                    body.append(l)
                if any(BACKTICK in b or DOLLAR_PAREN in b for b in body):
                    return m.group(2)
        return None

    d = unquoted_heredoc_with_subst(cmd)
    if d:
        print(f"unquoted heredoc <<{d} whose body has a backtick or dollar-paren substitution: the shell executes it before the reader "
              f"sees it (markdown code spans become commands). Quote the delimiter (<<'{d}'), or write the content to a "
              f"file with the Write tool. If substitution is intended, compute it into a variable first and use ${{var}}.")
        raise SystemExit(0)

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



def main():
    try:
        payload = json.load(sys.stdin)
        cmd = payload.get("tool_input", {}).get("command") or ""
        bg = bool(payload.get("tool_input", {}).get("run_in_background"))
        if not cmd:
            return 0
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            try:
                check(cmd, bg)
            except SystemExit:
                pass
        reason = out.getvalue().strip()
    except Exception as e:
        print(f"zsh-trap-guard: internal error, allowing ({type(e).__name__})", file=sys.stderr)
        return 0
    if reason:
        print(f"ZSH TRAP GUARD — blocked: {reason}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
