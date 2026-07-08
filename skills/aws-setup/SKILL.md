---
name: aws-setup
description: Set up AWS CLI SSO and sync TranslationService translations to S3
user_invocable: true
---

# AWS Setup — CLI Authentication & Translation Sync

Use this skill when AWS CLI credentials are needed (e.g., syncing translations to S3, accessing S3 buckets, or any `aws` command).

## Step 0: Read company config

```bash
cat ~/.claude/company-config.json 2>/dev/null | jq '.aws // empty'
```

Extract values into variables for use in subsequent steps:
- `profileName` — the AWS CLI profile name (default: `repo`)
- `ssoStartUrl` — SSO portal URL
- `ssoRegion` — SSO region
- `accountId` — AWS account ID
- `roleName` — SSO role name
- `defaultRegion` — default AWS region for services
- `s3TranslationsBucket` — S3 bucket for translations

If `company-config.json` is missing or has no `aws` section, ask the user for these values.

## Step 1: Check if AWS CLI is authenticated

```bash
bash ~/.claude/scripts/aws-check.sh
```

If this passes, skip to the task. If it fails, proceed to Step 2.

## Step 2: Check if `~/.aws/config` exists

```bash
cat ~/.aws/config 2>/dev/null
```

If missing or the profile doesn't exist, create it using values from Step 0:

```ini
[sso-session <profileName>]
sso_start_url = <ssoStartUrl>
sso_region = <ssoRegion>
sso_registration_scopes = sso:account:access

[profile <profileName>]
sso_session = <profileName>
sso_account_id = <accountId>
sso_role_name = <roleName>
region = <defaultRegion>
```

## Step 3: Authenticate

**Credentials are shared across all worktrees** — they live on disk in `~/.aws/credentials` / `~/.aws/sso/cache/`, NOT per-tmux/per-session. Before prompting anyone, re-check (`aws-check.sh`): if the parent or another worktree already logged in and the token is still valid, you already have access — just use it and continue, don't stop.

### Preferred: SSO login (nothing secret to copy)

When an `[sso-session <profileName>]` exists in `~/.aws/config` (it does for the standard setup), refresh via SSO — the user runs this in-session (e.g. `! aws sso login ...`) and approves in the browser; no keys are copied anywhere:

```bash
aws sso login --sso-session <profileName>
```

Then run aws commands with the matching SSO profile (boto3/CLI read the SSO cache directly), e.g. `AWS_PROFILE=<profileName>-sso <cmd>` — no static credentials needed. Verify with `bash ~/.claude/scripts/aws-check.sh`.

**SSO login troubleshooting (seen on this setup):** if `aws sso login` fails at `RegisterClient` / `StartDeviceAuthorization` with `InvalidRequestException` → `{"error":"invalid_request"}`:
- First clear a possibly-stale client registration: `rm -f ~/.aws/sso/cache/*.json` and retry.
- Try the device-code flow: `aws sso login --sso-session <profileName> --use-device-code`.
- If BOTH the auth-code and device-code flows still return `invalid_request` from the OIDC endpoint (reproduces in the user's own terminal, not just Claude's shell), the OIDC flow is broken environment-wide (Identity Center / CLI-version quirk) — **stop retrying** and use the temp-credential fallback below. Don't loop.

### Fallback: temp credentials (only if SSO login fails)

**Preferred fallback — Claude opens the file, user pastes into it (keys never touch the chat):**

1. Claude runs the helper, which seeds a `[default]` + `[<profileName>]` template (if the file is missing) and opens it in the OS editor:
   ```bash
   bash ~/.claude/scripts/aws-open-credentials.sh
   ```
2. The user opens `<ssoStartUrl>` → account → role → **"Access keys"**, copies the `aws_access_key_id` / `aws_secret_access_key` / `aws_session_token` values, pastes them over the `<paste>` placeholders under the single `[<profileName>]` header, and saves. Temp creds expire after ~8 hours.
3. Claude verifies (never sees the values): `aws sts get-caller-identity`.

The file lives on disk (`~/.aws/credentials`), so it's shared across all tmux sessions and worktrees.

**One profile, and it must match `AWS_PROFILE`.** The template seeds a single `[<profileName>]` block (e.g. `[repo]`). The standard setup exports `AWS_PROFILE=<profileName>` (Step 4 / `.zshrc`), so both the CLI and boto3 (the S3 sync) resolve to that profile — no `[default]` needed. If you seed `[default]` instead while `AWS_PROFILE=<profileName>` is exported, lookups fail with "Unable to locate credentials" — keep the header and the exported profile name in sync.

**Do NOT paste credentials into the Claude chat.** If a user pastes them anyway, use them to finish the task but tell them to rotate the creds afterward (they land in conversation history).

**Helper script caveat:** `bash ~/.claude/scripts/aws-set-credentials.sh "<ACCESS_KEY_ID>" "<SECRET_ACCESS_KEY>" "<SESSION_TOKEN>"` also works — but its `--from-exports` mode uses `grep -oP`, which is **broken on macOS/BSD grep** (writes garbage). On macOS, prefer the open-file-and-paste method above, or pass the 3 values as positional args.

**Note:** the static `[<profileName>]` credentials-file entry shadows the SSO `[profile <profileName>]` of the same name and expires after ~8 hours. Prefer the SSO profile (`<profileName>-sso`) when SSO works so a valid SSO cache is reused automatically.

## Step 4: Set up persistent profile

Suggest adding to `~/.zshrc` (or equivalent) so all terminals use the right profile:

```bash
echo 'export AWS_PROFILE=<profileName>' >> ~/.zshrc
```

## Sharing credentials across tmux sessions / worktrees

`~/.aws/credentials` lives **on disk, not per-session** — so once one session authenticates, **every other tmux session and worktree already shares the same credentials**. There is nothing to copy.

A session picks them up automatically as long as its shell exports the matching `AWS_PROFILE` (Step 4 adds this to `.zshrc`). To tell another Claude Code session:

> "AWS is already authenticated. Credentials are in `~/.aws/credentials` under the `[<profileName>]` profile, and `AWS_PROFILE=<profileName>` is exported. Run `aws` / boto3 commands directly — verify with `aws sts get-caller-identity`. If a command can't find creds, prefix it with `AWS_PROFILE=<profileName>`."

Notes:
- **Refresh once, shared everywhere.** When temp creds expire (`ExpiredToken`), re-run `bash ~/.claude/scripts/aws-open-credentials.sh` (or this skill) in any one session, paste fresh values, save — all other sessions immediately use the refreshed file.
- **"Unable to locate credentials"** in a session means its `AWS_PROFILE` doesn't match the file's profile header — export `AWS_PROFILE=<profileName>` (or prefix the command with it), and make sure the header in `~/.aws/credentials` matches.

## Common Tasks

### Sync TranslationService translations to S3

```bash
TRANSLATION_SERVICE_KEY=$(grep TRANSLATION_SERVICE_API_KEY apps/web/.env.local | cut -d= -f2)

python3 scripts/sync_lokalise_translations.py \
  --project-id 3907704568ac1345097c75.30587214 \
  --api-key "$TRANSLATION_SERVICE_KEY" \
  --s3-location <s3TranslationsBucket>
```

**Important:** The AWS env vars don't persist between shell invocations. If using temporary credentials, prepend them to the command or export them in the same `&&` chain.

### Verify a translation key exists in S3

```bash
curl -s "https://<s3TranslationsBucket>.s3.<defaultRegion>.amazonaws.com/en/en.json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
key='YOUR_KEY_HERE'
print(f'{key}: \"{d.get(key, \"NOT FOUND\")}\"')
"
```

## Key Details

Values come from `~/.claude/company-config.json` under the `aws` key. If not present, ask the user or check `~/.aws/config` for existing profiles.
