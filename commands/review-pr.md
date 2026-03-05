# Review PR — Code Review for Any Pull Request

## Config Resolution

Read `~/.claude/dtf-config.json` if it exists. Use:
- `paths.monorepo` instead of `~/Documents/Repo`
If no config exists, fall back to the values in `~/.claude/CLAUDE.md`.

Review a pull request with line-level comments on GitHub. Can approve, request changes, or leave advisory comments. Supports skipping files that aren't valuable to review (generated code, large diffs, lock files).

**Two modes:**
- **Fast (default)** — GitHub API only. No local checkout, minimal memory usage.
- **Full (`--full`)** — Checks out the branch into a temporary worktree for deeper analysis: runs builds, type checks, linting, and reviews with full codebase context.

## Input

The user provides a PR number, URL, or branch name. Optionally with flags. If **no PR is specified**, auto-detect from the current branch.

$ARGUMENTS

## Flags

- `--full` — Full mode: check out branch locally into a worktree, run builds/type checks/linting, review with full codebase context. Without this flag, review uses GitHub API only (fast mode).
- `--skip <pattern>` — Skip files matching the glob pattern (can be repeated). Examples: `--skip "*.generated.ts"`, `--skip "package-lock.json"`
- `--skip-large <N>` — Skip files with more than N lines changed (default: no limit)
- `--no-approve` — Never approve, only leave comments (advisory mode)
- `--focus <pattern>` — Only review files matching this pattern (ignore all others)

## Workflow

### Step 0: Resolve PR Identifier

If the user provided a PR number, URL, or branch name, use it directly.

If **no PR was specified** (arguments are empty or only flags), auto-detect from the current branch:

```bash
cd ~/Documents/Repo
gh pr view --json number,headRefName --jq '.number' 2>/dev/null
```

If this returns a number, use it. If it fails (no PR for the current branch), tell the user:
```
No PR found for the current branch. Please specify a PR number: /review-pr <number>
```

### Step 1: Fetch PR Details

```bash
cd ~/Documents/Repo
gh pr view <PR> --json number,title,body,author,baseRefName,headRefName,additions,deletions,url
```

Display a summary: title, author, base branch, total additions/deletions.

### Step 2: Get Changed Files with Stats

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/files --jq '.[] | "\(.filename)\t+\(.additions)\t-\(.deletions)\t\(.status)"'
```

### Step 2.5: Create Local Worktree (Full Mode Only)

**Skip this step entirely in fast mode.**

Full mode uses Claude Code's worktree conventions — worktrees live inside `.claude/worktrees/` and branches use the `worktree-` prefix. This keeps review worktrees alongside any other Claude-managed worktrees and ensures they're covered by `.gitignore`.

If `--full` was passed, create a temporary worktree for the PR branch:

```bash
cd ~/Documents/Repo
git fetch origin pull/<PR>/head:worktree-pr-review-<PR>
git worktree add .claude/worktrees/pr-review-<PR> worktree-pr-review-<PR>
```

If the fetch or worktree creation fails, fall back to fast mode and inform the user:
```
⚠ Could not create local worktree — falling back to fast (API-only) review.
```

Set a variable to track the worktree path for later cleanup: `WORKTREE=~/Documents/Repo/.claude/worktrees/pr-review-<PR>`

> **Experimental: Native worktree integration**
>
> Claude Code's `EnterWorktree` tool can create and manage worktrees natively with auto-cleanup on session exit. However, it currently creates from HEAD (not from a PR branch), so using it for PR review requires an extra fetch+checkout step inside the worktree. This approach is unsupported for now but may become the default when Claude Code adds branch targeting to `EnterWorktree`.
>
> If you want to try it: call `EnterWorktree` with name `pr-review-<PR>`, then `git fetch origin pull/<PR>/head:worktree-pr-review-<PR> && git checkout worktree-pr-review-<PR>` inside the worktree.

### Step 3: Apply File Filters

Build the list of files to review:

1. Start with all changed files
2. **Always skip** these by default (user can override with `--focus`):
   - `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`
   - `*.generated.ts`, `*.generated.tsx`
   - Files matching user's `--skip` patterns
3. If `--skip-large N` is set, skip files with more than N lines changed
4. If `--focus` is set, only include files matching that pattern

Show the user which files will be reviewed and which are skipped:

```
## Files to Review (7)
- src/components/ProfileCard.tsx (+45, -12)
- src/pages/employees/EmployeeCard.tsx (+20, -5)
- ...

## Skipped Files (3)
- package-lock.json (auto-skipped: lock file)
- src/store/rtk-apis/service-b/service-bApi.generated.ts (auto-skipped: generated file)
- ...
```

Ask the user to confirm, or let them adjust the skip list.

### Step 4: Read the Diff (Only Reviewed Files)

#### Fast mode (default)

Read the diff **per file** to keep memory usage low — don't load the entire PR diff at once if it's large:

```bash
# Get patch content per file from the API
gh api repos/{owner}/{repo}/pulls/<PR>/files --jq '.[] | select(.filename == "<FILE>") | .patch'
```

For files with very large patches (1000+ lines), summarize rather than reading every line.

#### Full mode (`--full`)

Read diffs locally from the worktree with full file context:

```bash
cd ~/Documents/Repo/.claude/worktrees/pr-review-<PR>
# Get the merge base for accurate diffs
BASE=$(git merge-base HEAD origin/<baseRefName>)
# Diff per file against the base branch
git diff $BASE..HEAD -- <FILE>
```

In full mode you also have access to the **complete file contents**, not just diff hunks. Use this to:
- Read the full file with the Read tool when you need surrounding context
- Check imports, types, and adjacent functions that aren't in the diff
- Understand how new code fits into the existing module

### Step 5: Check Existing Reviews

Don't duplicate feedback already given:

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/reviews --jq '.[] | "Author: \(.user.login) | State: \(.state)"'
gh api repos/{owner}/{repo}/pulls/<PR>/comments --jq '.[] | "\(.path):\(.line) | \(.user.login): \(.body[0:80])"'
```

### Step 5.5: Local Analysis (Full Mode Only)

**Skip this step entirely in fast mode.**

Run build and type checks in the worktree to catch compilation errors, type mismatches, and lint violations that aren't visible from diffs alone.

**Backend — if any `.cs`, `.csproj`, or `.sln` files changed:**

```bash
cd ~/Documents/Repo/.claude/worktrees/pr-review-<PR>
# Find the relevant solution file(s) for changed services
dotnet build services/<service>/<service>.sln 2>&1
```

Report any build errors or warnings related to the changed files.

**Frontend — if any files under `apps/web` changed:**

```bash
cd ~/Documents/Repo/.claude/worktrees/pr-review-<PR>/apps/web

# Type check
npx tsc --noEmit 2>&1

# Lint only changed files
npx eslint --no-error-on-unmatched-pattern <changed-frontend-files> 2>&1
```

Report any TypeScript errors or ESLint violations in the changed files.

**Tests — if test files were changed or added:**

```bash
# Frontend tests
cd ~/Documents/Repo/.claude/worktrees/pr-review-<PR>/apps/web && npx vitest run --reporter=verbose <changed-test-files> 2>&1

# Backend tests (if applicable)
cd ~/Documents/Repo/.claude/worktrees/pr-review-<PR> && dotnet test services/<service>/<service>.sln --filter "FullyQualifiedName~<test-class>" 2>&1
```

Include build/type/lint/test results in the review — any failures become **MUST FIX** items.

### Step 6: Review the Code

For each file's diff, check for:

**Code Quality:**
- Logic errors, off-by-one errors, null/undefined handling
- Missing error handling at system boundaries
- Unused imports, dead code
- Performance concerns (N+1 queries, unnecessary re-renders)

**Security (OWASP-aligned):**
- SQL injection, XSS, command injection
- Auth/authz issues (missing checks, wrong permission level)
- Sensitive data exposure (PII in logs, secrets in code)
- Path traversal

**Patterns & Conventions:**
- Naming conventions, component patterns
- i18n usage, API conventions
- React anti-patterns (missing deps, state misuse)
- EF Core patterns (async, proper includes)

**Additional checks in full mode (`--full`):**
- Verify imports resolve correctly (read the imported module if unsure)
- Check that new code follows patterns from adjacent files (read full files, not just diffs)
- Confirm types compile (use Step 5.5 results)
- Look for regressions in related tests (use Step 5.5 results)
- Check if new components/functions duplicate existing utilities (search the codebase)

For each issue, categorize as:
- **MUST FIX** — Bugs, security issues, broken patterns, build/type/test failures
- **SUGGESTION** — Style improvements, nice-to-haves
- **QUESTION** — Needs clarification from the author
- **PRAISE** — Good patterns worth highlighting

### Step 7: Present Review to User

Before posting to GitHub, show the full review:

```
## Review Summary: PR #1670 — "Add age field to profile card"

**Verdict:** Approve with suggestions

### MUST FIX (1)
1. `src/components/ProfileCard.tsx:42` — Missing null check on `employeeData.managers`

### SUGGESTION (2)
1. `src/components/ProfileCard.tsx:55` — Consider `useMemo` here
2. `src/utils/date.ts:30` — Could use existing helper `isAfterToday`

### QUESTION (1)
1. `src/pages/EmployeeCard.tsx:120` — Was the permission check intentionally removed?

### PRAISE (1)
1. `src/utils/date.ts:15` — Great use of `getDateWithoutTzConversion`
```

Ask the user:
- **"Post this review?"** — Options: "Yes, post as-is" / "Let me edit first" / "Post comments only (no verdict)" / "Cancel"

### Step 8: Post Review to GitHub

```bash
cat > /tmp/pr-review.json << 'REVIEW_EOF'
{
  "event": "<EVENT>",
  "body": "<SUMMARY>",
  "comments": [
    {
      "path": "<FILE_PATH>",
      "line": <LINE_NUMBER>,
      "body": "<COMMENT>"
    }
  ]
}
REVIEW_EOF

gh api -X POST repos/{owner}/{repo}/pulls/<PR>/reviews --input /tmp/pr-review.json
rm /tmp/pr-review.json
```

**Event mapping:**
- All SUGGESTION/PRAISE only → `"event": "APPROVE"`
- Any MUST FIX → `"event": "REQUEST_CHANGES"`
- `--no-approve` flag → `"event": "COMMENT"` (always)
- User chose "comments only" → `"event": "COMMENT"`

**Comment formatting:**
- Prefix each comment with its category in bold: `**MUST FIX**:`, `**SUGGESTION**:`, etc.
- Include code suggestions in fenced code blocks where applicable
- Keep comments concise — one issue per comment, actionable

### Step 9: Summary

Show the user:
- Link to the PR with review posted
- Count of comments by category

### Step 10: Cleanup Worktree (Full Mode Only)

**Skip this step entirely in fast mode.**

After the review is posted (or if the user cancels), always clean up the temporary worktree:

```bash
cd ~/Documents/Repo
git worktree remove .claude/worktrees/pr-review-<PR> --force
git branch -D worktree-pr-review-<PR>
git worktree prune
```

If cleanup fails, inform the user so they can clean up manually:
```
⚠ Could not remove worktree automatically. Run:
  cd ~/Documents/Repo && git worktree remove .claude/worktrees/pr-review-<PR> --force && git branch -D worktree-pr-review-<PR>
```

**Important:** Always attempt cleanup, even if the review was cancelled or an error occurred during earlier steps. Never leave orphaned worktrees.

## Important Rules

- **Always show the review to the user before posting** — never auto-post
- **Fast mode is API-only**: without `--full`, do NOT create worktrees, clone repos, or check out code locally. Read everything from the GitHub API.
- **Full mode always cleans up**: always remove the worktree and branch after the review, even on cancellation or error
- **Memory-efficient**: read diffs per file, not the entire PR diff at once for large PRs
- **Default skip list**: lock files and generated files are always skipped unless `--focus` overrides
- **Be specific**: every comment must have a file path and line number
- **Be balanced**: include PRAISE — reviews shouldn't be all negative
- **Don't nitpick**: skip trivial formatting if auto-formatters exist
- **Check existing reviews**: don't duplicate feedback already given
- **Line numbers**: use the line numbers from the diff/patch, which correspond to the new file version. The GitHub API `line` parameter refers to the line in the diff hunk.
- **Full mode failures degrade gracefully**: if worktree creation fails, fall back to fast mode. If builds/tests fail to run (missing deps, etc.), note it but continue the review.
