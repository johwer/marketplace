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
