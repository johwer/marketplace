# Reviewers — Manage PR Reviewer Assignments

Manage pre-configured GitHub reviewers per category, for adding extra reviewers on request. CODEOWNERS assigns the default reviewers when a PR goes ready; this list is opt-in on top of that.

## Input

$ARGUMENTS

## Categories

Valid categories: `frontend`, `backend`, `fullstack`, `infra`, `data`

## Config File

`~/.claude/reviewers.json` — source of truth. Structure:

```json
{
  "version": 1,
  "categories": {
    "frontend": ["github-user-1"],
    "backend": ["github-user-2"],
    "fullstack": ["github-user-1", "github-user-2"],
    "infra": [],
    "data": []
  }
}
```

## Subcommands

Parse the arguments to determine which subcommand to run.

### `list` (default if no args)

Read `~/.claude/reviewers.json` and display all categories with their reviewers:

```
## PR Reviewers

| Category   | Reviewers              |
|------------|------------------------|
| frontend   | @user1, @user2         |
| backend    | @user3                 |
| fullstack  | @user1, @user3         |
| infra      | (none)                 |
| data       | (none)                 |
```

### `add <category> <github-username>`

1. Validate the category is one of: `frontend`, `backend`, `fullstack`, `infra`, `data`. If not, show an error with valid options.
2. Read `~/.claude/reviewers.json`
3. Check if the username is already in that category — if so, say "already added"
4. Add the username to the category array
5. Write the updated JSON back
6. Confirm: "Added @username to **category** reviewers"

### `remove <category> <github-username>`

1. Validate the category
2. Read `~/.claude/reviewers.json`
3. Check if the username exists in that category — if not, say "not found"
4. Remove the username from the category array
5. Write the updated JSON back
6. Confirm: "Removed @username from **category** reviewers"

## How It's Used

`/my-dream-team` does not assign from this file: `.github/CODEOWNERS` requests reviewers when the PR goes ready. Use this list only when the user asks for extra or specific reviewers; then add that category's reviewers with `gh pr edit --add-reviewer`.

See `~/.claude/docs/dev-workflow-checklist.md` Section 4 for the full PR lifecycle.

## Sanitization

This file is sanitized by `sync-config.sh` for the public repo — GitHub usernames are replaced with generic placeholders (`reviewer-1`, `reviewer-2`, etc.).
