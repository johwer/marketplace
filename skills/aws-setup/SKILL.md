---
name: aws-setup
description: Set up AWS CLI SSO for Repo and sync TranslationService translations to S3
user_invocable: true
---

# AWS Setup — Repo CLI Authentication & Translation Sync

Use this skill when AWS CLI credentials are needed (e.g., syncing translations to S3, accessing S3 buckets, or any `aws` command).

## Step 1: Check if AWS CLI is authenticated

```bash
aws sts get-caller-identity 2>&1
```

If this returns credentials, skip to the task. If "Unable to locate credentials", proceed to Step 2.

## Step 2: Check if `~/.aws/config` exists

```bash
cat ~/.aws/config 2>/dev/null
```

If missing, create it:

```ini
[sso-session repo]
sso_start_url = https://d-9367b997a7.awsapps.com/start
sso_region = eu-north-1
sso_registration_scopes = sso:account:access

[profile repo]
sso_session = repo
sso_account_id = 107311625882
sso_role_name = Frontend-Developer
region = eu-west-1
```

## Step 3: Authenticate

Try SSO login first:
```bash
aws sso login --profile repo
```

If SSO login fails (common with some SSO configurations), use the **temporary credentials method**:

1. Tell the user: "Open https://d-9367b997a7.awsapps.com/start in your browser"
2. Click **Repo** → **Frontend-Developer** → **"Command line or programmatic access"**
3. Copy the 3 `export` lines (Option 1: environment variables)
4. User pastes them, you run them

Then verify:
```bash
aws sts get-caller-identity
```

## Common Tasks

### Sync TranslationService translations to S3

```bash
TRANSLATION_SERVICE_KEY=$(grep TRANSLATION_SERVICE_API_KEY apps/web/.env.local | cut -d= -f2)

python3 scripts/sync_lokalise_translations.py \
  --project-id 3907704568ac1345097c75.30587214 \
  --api-key "$TRANSLATION_SERVICE_KEY" \
  --s3-location repo-translations
```

**Important:** The AWS env vars don't persist between shell invocations. If using temporary credentials, prepend them to the command or export them in the same `&&` chain.

### Verify a translation key exists in S3

```bash
curl -s "https://repo-translations.s3.eu-west-1.amazonaws.com/en/en.json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
key='YOUR_KEY_HERE'
print(f'{key}: \"{d.get(key, \"NOT FOUND\")}\"')
"
```

## Key Details

| Item | Value |
|------|-------|
| SSO Portal | https://d-9367b997a7.awsapps.com/start |
| Account | Repo (107311625882) |
| Role | Frontend-Developer |
| S3 Bucket | repo-translations |
| S3 Region | eu-west-1 |
| Confluence Guide | https://your-company.atlassian.net/wiki/spaces/MEDHELP/pages/8151334915 |
