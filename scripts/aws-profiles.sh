#!/usr/bin/env bash
# aws-profiles.sh — manage AWS profiles without pasting keys every 8 hours.
#
# Subcommands:
#   sso      Log in via SSO (uses your Office 365 browser session), then DISCOVER every
#            account+role you have and write a profile for each into ~/.aws/config.
#            No keys are ever copied. Tokens auto-refresh.
#   list     Show every profile, which are SSO vs static, and which one is active.
#   check    Validate each profile with sts get-caller-identity (values never printed).
#   doctor   Repair ~/.aws/credentials: duplicate section headers, parse errors.
#   use <q>  Print the export line for the profile matching <q>.
#
# Why this exists: the portal hands you a block headed [<accountId>_<RoleName>]. Pasting it
# creates a profile whose name must match your exported AWS_PROFILE, and temp keys die after
# ~8h. SSO profiles solve both, and discovery means a new role (e.g. RDS-ReadOnly) appears
# without anyone editing config by hand.

set -uo pipefail

CONFIG="$HOME/.aws/config"
CREDS="$HOME/.aws/credentials"
COMPANY="$HOME/.claude/company-config.json"

SSO_SESSION="repo"
SSO_REGION="eu-north-1"
DEFAULT_REGION="eu-west-1"
if [[ -f "$COMPANY" ]] && command -v jq &>/dev/null; then
  SSO_REGION="$(jq -r '.aws.ssoRegion // "eu-north-1"' "$COMPANY")"
  DEFAULT_REGION="$(jq -r '.aws.defaultRegion // "eu-west-1"' "$COMPANY")"
fi

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

backup() { [[ -f "$1" ]] && cp "$1" "$1.bak-$(date +%s)"; }

# --- find the SSO access token the CLI cached after login -------------------
sso_token() {
  python3 - <<'PY'
import glob, json, os, sys, datetime
best = None
for f in glob.glob(os.path.expanduser("~/.aws/sso/cache/*.json")):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    if "accessToken" not in d:
        continue
    exp = d.get("expiresAt", "")
    try:
        e = datetime.datetime.fromisoformat(exp.replace("Z", "+00:00"))
        if e <= datetime.datetime.now(datetime.timezone.utc):
            continue
    except Exception:
        pass
    best = d["accessToken"]
if best:
    print(best)
else:
    sys.exit(1)
PY
}

cmd_doctor() {
  bold "Repairing $CREDS"
  [[ -f "$CREDS" ]] || { ok "No credentials file — nothing to repair (SSO needs none)."; return 0; }
  backup "$CREDS"
  python3 - "$CREDS" <<'PY'
import sys, configparser
p = sys.argv[1]
lines = open(p).read().splitlines()
out, prev = [], None
removed = 0
for ln in lines:
    s = ln.strip()
    if s.startswith("[") and s.endswith("]"):
        if s == prev:
            removed += 1
            continue
        prev = s
    elif s:
        prev = None
    out.append(ln)
open(p, "w").write("\n".join(out) + "\n")
if removed:
    print(f"  removed {removed} duplicate section header(s)")
c = configparser.ConfigParser()
try:
    c.read(p)
    print("  parses OK — profiles:", ", ".join(c.sections()) or "(none)")
except Exception as e:
    print("  STILL BROKEN:", type(e).__name__, e)
    sys.exit(1)
PY
}

cmd_list() {
  bold "SSO profiles (auto-refresh, no keys on disk)"
  python3 - "$CONFIG" <<'PY'
import sys, configparser
c = configparser.ConfigParser(); c.read(sys.argv[1])
rows = []
for s in c.sections():
    if not s.startswith("profile "): continue
    n = s[len("profile "):]
    if c.has_option(s, "sso_session"):
        rows.append((n, c.get(s,"sso_account_id",fallback="?"), c.get(s,"sso_role_name",fallback="?")))
print("  (none)" if not rows else "")
for n,a,r in sorted(rows):
    print(f"  {n:<44} {a}  {r}")
PY
  echo
  bold "Static profiles (temp keys, expire ~8h, SHADOW same-named SSO profiles)"
  if [[ -f "$CREDS" ]]; then
    grep '^\[' "$CREDS" 2>/dev/null | tr -d '[]' | sed 's/^/  /' || echo "  (none)"
  else
    echo "  (none)"
  fi
  echo
  bold "Active"
  echo "  AWS_PROFILE=${AWS_PROFILE:-(unset)}"
}

cmd_check() {
  local profiles
  profiles=$( { python3 - "$CONFIG" <<'PY'
import sys, configparser
c = configparser.ConfigParser(); c.read(sys.argv[1])
for s in c.sections():
    if s.startswith("profile "): print(s[len("profile "):])
PY
  } ; grep '^\[' "$CREDS" 2>/dev/null | tr -d '[]' )
  profiles=$(printf '%s\n' $profiles | sort -u)
  for p in $profiles; do
    printf '  %-44s ' "$p"
    if out=$(AWS_PROFILE="$p" aws sts get-caller-identity --query Arn --output text 2>&1); then
      ok "${out##*/}"
    else
      case "$out" in
        *ExpiredToken*)        warn "expired" ;;
        *Token*not*exist*|*sso*|*SSO*) warn "needs: aws sso login --sso-session $SSO_SESSION" ;;
        *)                     err "$(printf '%s' "$out" | head -1 | cut -c1-70)" ;;
      esac
    fi
  done
}

cmd_sso() {
  bold "1. Logging in via SSO (browser — your Office 365 session should carry you through)"
  if ! aws sso login --sso-session "$SSO_SESSION"; then
    warn "auth-code flow failed; retrying with device code"
    rm -f "$HOME"/.aws/sso/cache/*.json
    aws sso login --sso-session "$SSO_SESSION" --use-device-code || {
      err "SSO login failed both ways. Fall back to pasting keys:"
      err "  bash ~/.claude/scripts/aws-open-credentials.sh"
      exit 1
    }
  fi

  bold "2. Discovering the accounts and roles you actually have"
  local tok; tok=$(sso_token) || { err "no valid SSO token in cache after login"; exit 1; }

  local accounts
  accounts=$(aws sso list-accounts --access-token "$tok" --region "$SSO_REGION" \
              --output json 2>/dev/null) || { err "list-accounts failed"; exit 1; }

  backup "$CONFIG"
  python3 - "$CONFIG" "$SSO_SESSION" "$DEFAULT_REGION" "$SSO_REGION" "$tok" <<'PY'
import sys, json, subprocess, configparser
cfg_path, session, region, sso_region, tok = sys.argv[1:6]

accounts = json.loads(subprocess.run(
    ["aws","sso","list-accounts","--access-token",tok,"--region",sso_region,"--output","json"],
    capture_output=True, text=True, check=True).stdout)["accountList"]

c = configparser.ConfigParser()
c.read(cfg_path)
added, kept = [], []
for a in sorted(accounts, key=lambda x: x["accountId"]):
    aid, aname = a["accountId"], a.get("accountName","")
    roles = json.loads(subprocess.run(
        ["aws","sso","list-account-roles","--access-token",tok,"--account-id",aid,
         "--region",sso_region,"--output","json"],
        capture_output=True, text=True, check=True).stdout)["roleList"]
    for r in sorted(roles, key=lambda x: x["roleName"]):
        name = f"{aid}_{r['roleName']}"
        sec = f"profile {name}"
        existed = c.has_section(sec)
        if not existed:
            c.add_section(sec)
        c.set(sec, "sso_session", session)
        c.set(sec, "sso_account_id", aid)
        c.set(sec, "sso_role_name", r["roleName"])
        c.set(sec, "region", region)
        (kept if existed else added).append((name, aname))

with open(cfg_path, "w") as f:
    c.write(f)

print(f"  {len(added)+len(kept)} account/role pair(s) available")
for n, an in added: print(f"    + {n:<44} {an}")
for n, an in kept:  print(f"      {n:<44} {an}  (updated)")
PY

  echo
  bold "3. Static credentials that would SHADOW an SSO profile"
  local shadowed=0
  if [[ -f "$CREDS" ]]; then
    while read -r p; do
      if grep -q "^\[profile ${p}\]" "$CONFIG" 2>/dev/null; then
        warn "  [$p] in ~/.aws/credentials shadows the SSO profile of the same name"
        shadowed=1
      fi
    done < <(grep '^\[' "$CREDS" | tr -d '[]')
  fi
  if [[ $shadowed -eq 1 ]]; then
    echo
    echo "  Static keys win over SSO config for the same profile name, and they expire in ~8h."
    echo "  Once SSO works you do not need them. To retire them:"
    echo "    mv ~/.aws/credentials ~/.aws/credentials.retired-\$(date +%s)"
  else
    ok "  none"
  fi

  echo
  bold "4. Next"
  echo "  Pick a profile:   bash ~/.claude/scripts/aws-profiles.sh list"
  echo "  Verify them all:  bash ~/.claude/scripts/aws-profiles.sh check"
  echo "  Set the default in ~/.zshrc, e.g.:"
  echo "    export AWS_PROFILE=<accountId>_<RoleName>"
}

cmd_use() {
  local q="${1:-}"
  [[ -z "$q" ]] && { err "usage: aws-profiles.sh use <substring>"; exit 2; }
  local match
  match=$(python3 - "$CONFIG" "$q" <<'PY'
import sys, configparser
c = configparser.ConfigParser(); c.read(sys.argv[1]); q = sys.argv[2].lower()
hits = [s[len("profile "):] for s in c.sections()
        if s.startswith("profile ") and q in s.lower()]
print("\n".join(hits))
PY
)
  local n; n=$(printf '%s' "$match" | grep -c . || true)
  if [[ "$n" -eq 0 ]]; then err "no profile matching '$q'"; exit 1; fi
  if [[ "$n" -gt 1 ]]; then warn "ambiguous — matches:"; printf '%s\n' "$match" | sed 's/^/  /'; exit 1; fi
  echo "export AWS_PROFILE=$match"
}

case "${1:-}" in
  sso)    cmd_sso ;;
  list)   cmd_list ;;
  check)  cmd_check ;;
  doctor) cmd_doctor ;;
  use)    shift; cmd_use "$@" ;;
  *)
    bold "aws-profiles.sh — AWS profiles without pasting keys"
    echo
    echo "  sso      log in via SSO + auto-discover every account/role into ~/.aws/config"
    echo "  list     show SSO vs static profiles, and which is active"
    echo "  check    validate every profile (values never printed)"
    echo "  doctor   repair ~/.aws/credentials (duplicate headers, parse errors)"
    echo "  use <q>  print the export line for a profile"
    ;;
esac
