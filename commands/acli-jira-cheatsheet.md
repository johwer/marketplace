# ACLI Jira Cheatsheet

Everything is under **`acli jira workitem`** (there is no `issue` subcommand).

## Viewing / Searching Tickets

**View a specific ticket:**
```bash
acli jira workitem view KEY-123
acli jira workitem view KEY-123 --fields summary,comment
acli jira workitem view KEY-123 --web          # opens in browser
```

**Search tickets (list):**
```bash
# By JQL query
acli jira workitem search --jql "project = TEAM"
acli jira workitem search --jql "project = TEAM AND assignee = currentUser()"

# Choose output format
acli jira workitem search --jql "project = TEAM" --csv
acli jira workitem search --jql "project = TEAM" --json

# Pick specific fields & limit results
acli jira workitem search --jql "project = TEAM" --fields "key,summary,assignee,status" --limit 50

# Get total count
acli jira workitem search --jql "project = TEAM" --count

# By saved filter
acli jira workitem search --filter 10001
```

## Creating Tickets

```bash
# Basic creation
acli jira workitem create --project "TEAM" --type "Task" --summary "New Task"

# With more details
acli jira workitem create \
  --project "TEAM" \
  --type "Bug" \
  --summary "Login broken" \
  --description "Steps to reproduce..." \
  --assignee "user@example.com" \
  --label "bug,critical"

# Self-assign
acli jira workitem create --project "TEAM" --type "Task" --summary "My task" --assignee @me

# From a JSON template (generate one first, then edit it)
acli jira workitem create --generate-json
acli jira workitem create --from-json workitem.json

# Open editor for summary/description
acli jira workitem create --project "TEAM" --type "Task" --editor
```

## Editing Tickets

```bash
# Edit by key
acli jira workitem edit --key "KEY-123" --summary "Updated title"
acli jira workitem edit --key "KEY-123" --assignee "user@example.com"
acli jira workitem edit --key "KEY-123" --description "New description"

# Bulk edit by JQL
acli jira workitem edit --jql "project = TEAM AND status = 'To Do'" --assignee @me --yes

# Change status (transition)
acli jira workitem transition --key "KEY-123" --status "In Progress"
acli jira workitem transition --key "KEY-123" --status "Done"

# Bulk transition (use --yes to skip confirmation prompt)
acli jira workitem transition --key "KEY-1,KEY-2,KEY-3" --status "Done" --yes
```

## Other Useful Operations

| Action | Command |
|---|---|
| **Assign** | `acli jira workitem assign --key KEY-123 --assignee @me` |
| **Add comment** | `acli jira workitem comment create --key KEY-123 --body "my comment"` |
| **Add labels** | `acli jira workitem edit --key KEY-123 --labels "bug,urgent"` |
| **Clone** | `acli jira workitem clone --key KEY-123` |
| **Delete** | `acli jira workitem delete --key KEY-123` |
| **List sprint items** | `acli jira sprint list-workitems --sprint-id 123` |

Append `--help` to any command to see its full options.

## Custom Fields via REST API

ACLI doesn't support custom fields (like story points) for editing. Use the helper script that extracts the ACLI OAuth token from macOS keychain and calls the Jira REST API directly.

```bash
# Set story point estimate
bash ~/.claude/scripts/jira-set-field.sh PROJ-123 customfield_10437 4

# Set any custom field (text values need quotes)
bash ~/.claude/scripts/jira-set-field.sh PROJ-123 customfield_10999 '"some text"'
```

**Known custom field IDs (PLRS project):**

| Field ID | Name |
|---|---|
| `customfield_10437` | Story point estimate |
| `customfield_10124` | Story Points (legacy) |

**Finding field IDs for other custom fields:**
The script uses the same OAuth token pattern as `jira-download-attachments.sh`. To discover field IDs:
```bash
# List all fields containing a keyword
ACCESS_TOKEN=$(security find-generic-password -s "acli" -w | python3 -c "
import sys, base64, gzip, json
d = sys.stdin.read().strip()[len('go-keyring-base64:'):]
print(json.loads(gzip.decompress(base64.b64decode(d)))['access_token'])")
CLOUD_ID="4f617dfc-e4b4-4019-826c-6d9df112d610"
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/field" | \
  python3 -c "import sys,json;[print(f'{f[\"id\"]}: {f[\"name\"]}') for f in json.load(sys.stdin) if 'keyword' in f['name'].lower()]"
```

## Attachments

```bash
# Download all attachments from a ticket
bash ~/.claude/scripts/jira-download-attachments.sh PROJ-123 [output-dir]
```
