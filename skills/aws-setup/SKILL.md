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

Tell the user:

1. Open `<ssoStartUrl>` in your browser
2. Click the account → role → **"Command line or programmatic access"**
3. Copy the 3 values: **Access key ID**, **Secret access key**, **Session token**

Then run the credential helper — it writes to `~/.aws/credentials` which **persists across all terminals and worktrees**:

```bash
bash ~/.claude/scripts/aws-set-credentials.sh "<ACCESS_KEY_ID>" "<SECRET_ACCESS_KEY>" "<SESSION_TOKEN>"
```

Verify:
```bash
bash ~/.claude/scripts/aws-check.sh
```

**Note:** `aws sso login` is the standard approach but fails for some SSO configurations. The credentials-file method works reliably. Credentials expire after ~8 hours — re-run when needed.

## Step 4: Set up persistent profile

Suggest adding to `~/.zshrc` (or equivalent) so all terminals use the right profile:

```bash
echo 'export AWS_PROFILE=<profileName>' >> ~/.zshrc
```

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
