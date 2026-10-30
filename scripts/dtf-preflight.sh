#!/usr/bin/env bash
# dtf-preflight.sh — environment checks a DTF session needs BEFORE it plans a real-browser pass,
# a push, or an LFS-tracked commit. Run at /my-dream-team start (Phase 1 step 0), not at Phase 4.75.
#
# Usage: bash ~/.claude/scripts/dtf-preflight.sh [WORKTREE] [--no-login]
#
# Why a script: in PROJ-4294 all four of these failed mid-session, each discovered only when the
# step that needed it ran (after implementation). PROJ-4185/4389/4421 hit the same class.
#
# Exit 0 = all PASS (WARNs allowed). Exit 1 = at least one FAIL — tell the user before planning
# work that depends on the failed item.
set -uo pipefail

WORKTREE="${1:-$PWD}"
[[ "${1:-}" == "--no-login" ]] && WORKTREE="$PWD"
NO_LOGIN=false
for a in "$@"; do [[ "$a" == "--no-login" ]] && NO_LOGIN=true; done

FAILS=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILS=$((FAILS + 1)); }

echo "▸ DTF preflight ($WORKTREE)"

if command -v playwright-cli >/dev/null 2>&1; then
  pass "playwright-cli on PATH ($(command -v playwright-cli))"
else
  fail "playwright-cli missing — npm i -g @playwright/cli@0.1.22 (for the Node in use: $(node -v 2>/dev/null || echo none)), or use 'npx @playwright/cli'"
fi

if command -v git-lfs >/dev/null 2>&1; then
  pass "git-lfs on PATH"
else
  fail "git-lfs missing — pushes of LFS-tracked files will fail (brew install git-lfs)"
fi

SSH_OUT=$(ssh -T -o ConnectTimeout=5 -o BatchMode=yes git@github.com 2>&1 || true)
if grep -q "successfully authenticated" <<<"$SSH_OUT"; then
  pass "GitHub SSH :22 reachable"
  # :22 flapped ten minutes after a passing preflight (PROJ-4568) and :443 then failed host-key
  # verification, so print the HTTPS route up front even on a pass.
  if gh auth status >/dev/null 2>&1; then
    warn "if :22 drops later, push via HTTPS: git -c credential.helper='!gh auth git-credential' push https://github.com/<OWNER>/<REPO>.git HEAD:<branch>"
  fi
else
  SSH443=$(ssh -T -p 443 -o ConnectTimeout=5 -o BatchMode=yes git@ssh.github.com 2>&1 || true)
  if grep -q "successfully authenticated" <<<"$SSH443"; then
    warn "SSH :22 blocked; :443 works — push with: git push ssh://git@ssh.github.com:443/<OWNER>/<REPO>.git HEAD:<branch>"
  elif gh auth status >/dev/null 2>&1; then
    warn "SSH unreachable; HTTPS via gh works — push with: git -c credential.helper='!gh auth git-credential' push https://github.com/<OWNER>/<REPO>.git HEAD:<branch>"
  else
    fail "no route to GitHub (SSH :22, SSH :443 and gh auth all failed)"
  fi
fi

# Reaching github.com is not being allowed to push to THIS remote: PROJ-4696 passed the :22
# check and then `git push origin` was refused (access rights). A dry-run push opens
# git-receive-pack with the real remote URL and credentials, which GitHub refuses without write
# access; nothing is sent.
if git -C "$WORKTREE" remote get-url origin >/dev/null 2>&1; then
  PROBE_REF="refs/heads/dtf-preflight-probe-$$"
  if GIT_SSH_COMMAND="ssh -o ConnectTimeout=8 -o BatchMode=yes" GIT_TERMINAL_PROMPT=0 \
      git -C "$WORKTREE" push --dry-run --no-verify origin "HEAD:$PROBE_REF" >/tmp/dtf-preflight-push.log 2>&1; then
    pass "authenticated push to origin works (dry-run)"
  elif gh auth status >/dev/null 2>&1; then
    warn "git push origin refused ($(grep -m1 -iE 'denied|error|fatal' /tmp/dtf-preflight-push.log)); HTTPS via gh: git -c credential.helper='!gh auth git-credential' push https://github.com/<OWNER>/<REPO>.git HEAD:<branch>"
  else
    fail "git push origin refused and gh is not authenticated — see /tmp/dtf-preflight-push.log"
  fi
fi

# GitGuardian scans every PR commit; a hit after push costs a history rewrite (PROJ-4465).
if command -v ggshield >/dev/null 2>&1; then
  pass "ggshield on PATH (quality-gate scans the branch range before push)"
else
  warn "ggshield missing — secrets are only caught by GitGuardian AFTER push (brew install ggshield && ggshield auth login)"
fi

# Shared service-c/service-a codegen writes into apps/mobile too; its tests and type-check need
# apps/mobile/node_modules, and `npm ci --ignore-scripts` skips the translation postinstall (PROJ-4467).
if [[ -d "$WORKTREE/apps/mobile" && ! -d "$WORKTREE/apps/mobile/node_modules" ]]; then
  warn "apps/mobile/node_modules missing — if this ticket regenerates shared API clients, run 'npm ci' in apps/mobile (not --ignore-scripts); quality-gate FAILs once the branch touches apps/mobile"
fi

if [[ "$NO_LOGIN" == "true" ]]; then
  warn "seed login check skipped (--no-login)"
elif [[ -f "$WORKTREE/scripts/local-api-login.sh" ]]; then
  if (cd "$WORKTREE" && bash scripts/local-api-login.sh) >/tmp/dtf-preflight-login.log 2>&1; then
    pass "seed login returns a token (shared stack is seeded)"
  else
    fail "seed login failed — the shared stack is down or unseeded. STOP and ask before planning a post-login check (see /tmp/dtf-preflight-login.log)"
  fi
else
  warn "no scripts/local-api-login.sh in $WORKTREE — seed login not checked"
fi

if [[ $FAILS -gt 0 ]]; then
  echo "  → $FAILS FAIL(s). Report them to the user now, not at the phase that needs them."
  exit 1
fi
echo "  → preflight clean"
