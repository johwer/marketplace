# AWS access — set up once, then forget it

How to get AWS credentials on a Repo dev machine. The short version: **run one command, click
once in the browser, never copy a key.**

```bash
bash ~/.claude/scripts/aws-profiles.sh sso
```

That logs in through AWS Identity Center (your Office 365 session usually carries you straight
through) and then discovers **every account and role you actually hold**, writing a profile for each
into `~/.aws/config`. You do not need to know account IDs in advance, and a role granted to you later
appears the next time you run it.

## What you end up with

One profile per account/role, named the way the AWS portal names them:

```
123456789012_YourRoleName        Repo (S3 translations)
753423979104_RDS_tt-accept_main        tt-accept RDS (Finnish market)
<account>_RDS_mh-accept_main           mh-accept RDS (Swedish market; not the "Repo" account)
```

`RDS-ReadOnly_tt-accept` no longer exists (`ForbiddenException: No access`): anything still naming it is broken.

Set your everyday one as the default in `~/.zshrc`:

```bash
export AWS_PROFILE=123456789012_YourRoleName
```

and reach for the others per command:

```bash
AWS_PROFILE=753423979104_RDS_tt-accept_main aws <cmd>
eval $(bash ~/.claude/scripts/aws-profiles.sh use rds)   # or switch the current shell
```

## The commands

| Command | What it does |
|---|---|
| `aws-profiles.sh sso` | Log in + discover every account/role into `~/.aws/config` |
| `aws-profiles.sh list` | SSO vs static profiles, and which is active (flags a stale `AWS_PROFILE`) |
| `aws-profiles.sh check` | Validate every profile via STS — values are never printed |
| `aws-profiles.sh doctor` | Repair `~/.aws/credentials` (duplicate headers, parse errors) |
| `aws-profiles.sh use <q>` | Print the `export` line for a matching profile |

## How often do I have to click the browser?

Only when the SSO **session** expires, not per command. Within the session the CLI refreshes silently
using a refresh token, so a single login normally covers days. Session length is set by the Identity
Center admins, not by anything local.

When it does expire you will see an expired/SSO error. Re-run `aws-profiles.sh sso`. That is the whole
maintenance burden: one command, one click, occasionally.

**It cannot be fully automated, and that is deliberate** — the browser step is the human-presence check
in the OAuth device/auth-code flow. Anything that removed it would be a way of bypassing your MFA.

## Do NOT paste static keys

The portal will happily give you a block of temp keys. Resist it, for two concrete reasons:

1. **They expire in ~8 hours.** That was the old routine and it wasted a lot of time.
2. **They silently shadow SSO.** A static profile in `~/.aws/credentials` wins over an SSO profile of
   the same name — and the portal's block is named `[<accountId>_<RoleName>]`, exactly matching the SSO
   profile names. So pasting reintroduces expiry for a profile that was working fine.

If keys were pasted before, retire them once SSO works:

```bash
mv ~/.aws/credentials ~/.aws/credentials.retired-$(date +%s)
```

## Troubleshooting

Work down this list. Each step is cheap and rules out a whole class of problem.

**"The config profile (x) could not be found"** — a stale exported `AWS_PROFILE`. The shell predates a
profile rename. Open a new terminal, or re-export. This breaks even `aws sso login`, which needs no
profile at all, so it is easy to mistake for broken SSO. `aws-profiles.sh list` flags it.

**"I pasted keys and it still says expired"** — the file is probably corrupt. Pasting the portal block
twice leaves a duplicate `[<accountId>_<RoleName>]` header, which makes the **entire file** unparseable,
so *every* profile reports expired including ones with valid keys. Run `aws-profiles.sh doctor`.

**`InvalidRequestException` with an empty message** — the `sso_region` is wrong. This is not SSO being
broken, and retrying will not help. `StartDeviceAuthorization` validates the start URL against the
Identity Center instance in the region you name, so only the correct region succeeds:

```bash
unset AWS_PROFILE
for r in eu-west-1 eu-north-1 eu-central-1 us-east-1; do
  REG=$(aws sso-oidc register-client --client-name p --client-type public \
        --scopes sso:account:access --region "$r" --output json 2>/dev/null)
  CID=$(echo "$REG" | python3 -c "import sys,json;print(json.load(sys.stdin)['clientId'])" 2>/dev/null)
  CSEC=$(echo "$REG" | python3 -c "import sys,json;print(json.load(sys.stdin)['clientSecret'])" 2>/dev/null)
  [ -z "$CID" ] && continue
  aws sso-oidc start-device-authorization --client-id "$CID" --client-secret "$CSEC" \
    --start-url https://d-EXAMPLE.awsapps.com/start --region "$r" 2>/dev/null \
    | grep -q verificationUriComplete && echo "$r <-- instance is here"
done
```

Note that plain `register-client` succeeds in **every** region — that is the misleading part. Only the
device-authorization call discriminates. Put the winning region in `~/.aws/config` *and*
`company-config.json` (so `dtf install` propagates it), clear `~/.aws/sso/cache/*.json`, log in again.

**Accept RDS fails with `password authentication failed`** — DB access needs three things and only the
first shows in the portal: (1) the `RDS_<env>_main` permission set, (2) `rds-db:connect` on your dbuser
ARN, (3) a DB role in the cluster (`CREATE USER "<you>" LOGIN; GRANT rds_service-c, pg_read_all_data`). Nothing
propagates 2 and 3 between environments, and both fail exactly like a wrong password. `aws rds
generate-db-auth-token` proves nothing (it signs locally). Probe with the repo's
`scripts/test/probe-accept-auth.sh`, never with a clone (it drops the shared local databases). Needs the
VPN: without it psql fails at once with "Network is unreachable"; retry the first `nc` after connecting.

**A role authenticates but an API call is denied** — that is the role's ServiceC scope, not your setup. For
example the RDS role cannot call `rds:DescribeDBInstances`; despite the name it grants
database *data* access (a DB user / `rds-db:connect`), not the RDS control plane. Check
`aws sts get-caller-identity` first: if that works, credentials are fine and the problem is permissions.

## Historical note

Until 2026-08-18 `sso_region` was set to `eu-north-1` while the instance is in `eu-west-1`. SSO
appeared permanently broken, and the documented workaround was to paste temp keys every 8 hours. It
was a one-line config error. If you are reading old notes that say "OIDC is broken environment-wide",
they are wrong — that guidance has been removed.
