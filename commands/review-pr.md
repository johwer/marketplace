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
- `--deep` — Multi-agent review with validation. Launches 7 parallel review agents (2x convention, 2x bug/security, 1x historical context, 1x improvement, 1x structural), then validates each finding with independent agents. **Every surviving finding carries a concrete proposed change.** Implies `--full` (the validation gate needs a checkout — see 6e). Significantly more thorough but uses more tokens.
- `--no-improve` — With `--deep`, skip the improvement and structural agents (6 and 7). Use when you only want correctness and convention findings.
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

**If `--deep` flag is NOT set**, do a standard single-pass review (the default — fast and token-efficient):

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
- **SUGGESTION** — Convention concerns that aren't blocking
- **IMPROVEMENT** — A better shape for working code: reuse of an existing helper, a simplification, a structural fix. Needs a stated trade-off.
- **PRAISE** — Good patterns worth highlighting

The proposal gate applies here too, without the multi-agent machinery: **every MUST FIX, SUGGESTION and IMPROVEMENT carries replacement code, or it is dropped.** Verify the claim against the repository before writing the fix — open the file, grep the call sites, read the imported module. Anything you could look up is not a question; see **Important Rules**.

**Skip to Step 7.**

---

### Step 6 Deep: Multi-Agent Review with Validation (`--deep`)

**If `--deep` flag IS set**, replace the single-pass review with a multi-agent pipeline. This is significantly more thorough but uses more tokens.

`--deep` implies `--full`: 6e validates against the repository rather than the diff hunk, which needs the worktree from Step 2.5. If the worktree could not be created, say so up front and stop — a deep review that silently validates from diffs produces confident findings with no evidence behind them, which is the failure this pipeline exists to prevent.

#### 6a. Gate Check

Before spawning review agents, check if this PR is worth a deep review:

```bash
gh pr view <PR> --json state,isDraft,additions,deletions,reviews --jq '{state: .state, draft: .isDraft, changes: (.additions + .deletions), reviewed: ([.reviews[] | select(.author.login == "claude" or .author.login == "github-actions")] | length)}'
```

**Skip deep review** (fall back to standard Step 6) if:
- PR is closed or merged
- PR is a draft (use `--deep` on draft PRs only if explicitly forced)
- Total changes < 10 lines (trivial)
- Claude has already reviewed this PR (check reviews list)

If skipping, inform the user: `"Skipping deep review — [reason]. Running standard review instead."`

#### 6b. Collect Convention Context

Gather the relevant convention files for the changed directories:

```bash
# Find CLAUDE.md / AGENTS.md files in affected directories
for dir in $(gh api repos/{owner}/{repo}/pulls/<PR>/files --jq '.[].filename' | xargs -I{} dirname {} | sort -u); do
  echo "--- $dir ---"
  # Check if AGENTS.md or CLAUDE.md exists in that directory or parents
done
```

Also read project-level conventions:
- `docs/CODING_STYLE_BACKEND.md` (if .cs files changed)
- `docs/CODING_STYLE_FRONTEND.md` (if .ts/.tsx files changed)
- `docs/API_CONVENTIONS.md` (if API routes changed)

Compile a **conventions summary** — a condensed bullet list of the rules that apply to this PR's changed files. This will be passed to all review agents so they don't each re-read the full docs.

#### 6c. Spawn 4 Parallel Review Agents

Split the changed files into two halves (by file count). Launch 4 agents **in parallel** using the Agent tool:

**Agent 1: Convention Reviewer A** (Sonnet)
- Reviews first half of changed files
- Prompt: "You are a convention reviewer. Check these diffs against the conventions summary below. Flag ONLY clear, unambiguous violations where you can quote the exact rule broken. Do NOT flag style preferences, subjective improvements, or things a formatter would catch. For each issue, return: `{file, line, category: 'MUST FIX'|'SUGGESTION', description, convention_violated}`."
- Include: conventions summary, diff patches for files in first half

**Agent 2: Convention Reviewer B** (Sonnet)
- Reviews second half of changed files
- Same prompt as Agent 1, different files

**Agent 3: Bug & Security Hunter A** (Opus)
- Reviews ALL changed files (not split — bugs need full context)
- Prompt: "You are a bug and security reviewer. Scan these diffs for: (a) code that will fail to compile or produce wrong results regardless of input, (b) security vulnerabilities (OWASP top 10), (c) clear logic errors. Do NOT flag: style concerns, potential issues that depend on specific state, subjective improvements, pre-existing issues, things a linter catches. For each issue, return: `{file, line, category: 'MUST FIX', description, evidence}`."
- Include: diff patches for all files

**Agent 4: Bug & Security Hunter B** (Opus)
- Same scope as Agent 3 but different focus
- Prompt: "You are a security and correctness reviewer. Focus on: (a) auth/authz issues — missing permission checks, broken access control, privilege escalation, (b) data exposure — sensitive fields in API responses, PII in logs, (c) injection vectors — SQL, XSS, command injection, path traversal. Also check: are there new API endpoints without `[Authorize]`? New `UserAction` values without backend enforcement? For each issue, return: `{file, line, category: 'MUST FIX', description, evidence}`."
- Include: diff patches for all files

**Agent 5: Historical Context Reviewer** (Sonnet)
- Reviews ALL changed files through the lens of prior history (not just the current diff)
- Prompt: "You are a historical context reviewer. For each changed file, investigate prior work and review history. Your job is to catch patterns that were already rejected or fixes that this PR is silently undoing — things the diff-only reviewers cannot see.
  - For each file, run: `gh api repos/{owner}/{repo}/commits?path=<file>&per_page=5 --jq '.[] | {sha, message: .commit.message, date: .commit.author.date}'` to see the last 5 commits touching it.
  - Then: `gh search prs --repo {owner}/{repo} <file path> --state merged --limit 5 --json number,title,url` to find prior merged PRs touching it.
  - For the top 2–3 prior PRs, run: `gh pr view <num> --comments` and scan the review threads.
  - Flag MUST FIX only if you find concrete evidence: (a) this PR reverts a deliberate prior fix without explanation in the PR description/commit message, or (b) this PR repeats a pattern that was explicitly pushed back on in a prior PR review. Quote the prior commit message or review comment as evidence.
  - Known recurring patterns to look for (cite these by name if you find them): action-based REST routes (should be resource-based), upsert misuse on user-preference tables, exception-as-flow control, cross-service responsibility leaks (ServiceC concerns edited in ServiceB/ServiceA), missing HTML encoding before email template substitution, CompanyPermission vs UserPermission misuse on company-level actions, missing multi-tenancy validation (companyIds belonging to customerId), EF Core SetValues() on entities with immutable fields.
  - Do NOT flag stylistic regressions, formatter-catchable issues, or patterns that were merely discussed but not concluded. Only flag if there is a clear prior decision being violated.
  - For each issue return: `{file, line, category: 'MUST FIX'|'SUGGESTION', description, evidence: 'PR#<num>: \"<quoted comment>\"' or 'Commit <sha>: \"<commit msg>\"'}`."
- Include: list of changed file paths, repo owner/name (parse from `gh repo view --json owner,name`)
- Works in both fast mode and `--full` mode — all queries go through `gh` API, no local worktree required

**Agent 6: Improvement Reviewer** (Sonnet) — skip if `--no-improve`
- Reviews ALL changed files
- **First, read `~/.claude/skills/code-insights/SKILL.md`** and use its Mode 1 pattern tables as the checklist. Do not restate them here — that file is the source of truth, so it stays correct as the conventions move. Note in particular its React 19 rule: never propose `useMemo`/`useCallback`/`React.memo`, the compiler handles them.
- Prompt: "You are an improvement reviewer. Your output is better code, not observations. For each finding you MUST supply a `proposal` containing the actual replacement code — not a description of it. If you cannot write the replacement, the finding does not exist: drop it. Also supply the trade-off, because a proposal with no cost is usually a proposal you haven't thought through. Return: `{file, line, category: 'IMPROVEMENT', description, proposal: '<code>', tradeoff, evidence}`."

**Agent 7: Structural Reviewer** (Opus) — skip if `--no-improve`
- Reviews ALL changed files
- **First, read `.claude/skills/quality-review/patterns/design-quality.md` and `structural-health.md`** from the repo under review (plus `replay-safety.md` only if the diff touches messaging, handlers, or event consumers). Those pattern files are the source of truth for the dimensions.
- Also apply `improve-codebase-architecture`'s boundary lens, but **to the diff only**: did this change make a module boundary worse, add a shallow module, or push a responsibility into the wrong service? A whole-module audit is that command's job, not this one's.
- Prompt: "You are a structural reviewer. Same hard rule as the improvement reviewer: every finding carries a `proposal` with real replacement code, or it is dropped. Reject your own findings that add abstraction or code without reducing the number of concepts a reader must hold. Return: `{file, line, category: 'IMPROVEMENT', description, proposal: '<code>', tradeoff, evidence}`."

**Wait for all agents to complete.** Collect their findings into a combined issue list.

#### 6d. Deduplicate

Merge the 5 agents' issue lists:
- If two agents flagged the same file:line with the same concern → keep one, note "flagged by 2 agents" (higher confidence)
- If issues overlap but aren't identical → keep both, they may be different aspects

#### 6e. Validation Pass

For each issue from 6d, spawn a **validation agent** to independently verify it. Run validations in parallel (batch of up to 8 at a time).

Validation here does two jobs, and the second one is why this step exists: it decides whether the finding is real, **and it makes the proposal correct**. A finding that survives with the wrong fix attached is worse than no finding — the author implements it and the reviewer has cost them time twice.

**Validation agent prompt** (Sonnet for convention issues, Opus for bug/security and IMPROVEMENT issues):

```
You are validating a finding from a multi-agent review. The repository root is {REPO_ROOT}.

FINDING: {finding JSON, including its proposal}

Do not judge this from the diff hunk. Open the repository and establish the facts:
- Read the file at {file}:{line} and enough surrounding code to judge independently.
- Grep for the other call sites, the sibling implementations, the token definitions, the
  type declaration — whatever the claim actually rests on.
- If the claim rests on a library's behaviour, read that library's source under
  node_modules rather than recalling it.
- If the claim is that something is missing, absent, or "the only one", run the search
  that would disprove it and paste what came back.
- If the claim is about intent or a prior decision, run git log / git blame.

TWO HARD GATES — a finding fails if either is unmet:

1. EVIDENCE. You must name the artifact you read: a file:line you opened, a command
   and its actual output, a git log line, or a dependency source path. Reasoning that
   never left the diff is not evidence. Findings without evidence are DROPPED, not
   downgraded — an unverified claim handed to the author as a question is work moved,
   not work done.

2. PROPOSAL. The finding must carry replacement code that is correct against what you
   just read. If the supplied proposal is wrong, fix it and say what you changed. If no
   concrete replacement can be written, the finding is DROPPED. "Consider whether…",
   "should this be…", and "was this intentional?" are not findings.

Apply the nine hard exclusions in `.claude/skills/quality-review/SKILL.md` Phase 2
verbatim (formatting covered by tooling, naming preferences, untouched pre-existing code,
speculative future cost, approach complaints with no sketchable alternative, test-file
nits below HIGH, micro-optimisation, abstraction that does not reduce concept count,
docs-only). That list is the source of truth — read it, don't work from memory.

Output: {
  "finding_id": "...",
  "confidence": 1-10,      // 1-3 dismiss, 4-6 plausible but weak, 7-10 worth raising
  "evidence": "...",       // the artifact, quoted
  "proposal": "...",       // corrected replacement code
  "proposal_changed": bool,
  "reasoning": "..."
}
```

Include in the validation prompt: the flagged issue with its proposal, the relevant diff hunk, and the repository root. **This step needs a checkout**, which is why `--deep` implies `--full`. If the worktree is unavailable, say so in the output and treat every finding as evidence-less — do not silently fall back to diff-only validation and present the result as verified.

#### 6f. Filter

Drop every finding with `confidence <= 6`, no `evidence`, or no `proposal`. Report the three reasons separately — they mean different things, and collapsing them hides which part of the pipeline is misfiring:

```
Deep review: 7 agents found 19 findings
  → 4 dropped: no evidence (claim never left the diff)
  → 3 dropped: no concrete proposal
  → 3 dropped: confidence <= 6
  → 9 survive, 2 with a corrected proposal
```

If `proposal_changed` is true for a finding, the validator rewrote the fix. Present the corrected version — never the agent's original.

#### 6g. Merge with Build Results

If `--full` mode was also active (i.e., `--deep --full`), merge the validated issues with any build/type/lint/test failures from Step 5.5. Build failures are always MUST FIX and skip validation (they're deterministic).

#### 6h. Final Categorization

Categorize all surviving issues. Every entry in the first three carries replacement code:
- **MUST FIX** — Confirmed bugs, security issues, build failures, clear convention violations
- **SUGGESTION** — Confirmed convention concerns that aren't blocking
- **IMPROVEMENT** — A better shape for code that already works: reuse of an existing helper or primitive, a simplification, a structural fix. Requires a stated trade-off. Cap at the top 5 by impact — an unbounded list of nudges gets skimmed and teaches the author to skim the next one too.
- **PRAISE** — Good patterns noticed by any agent (pass-through, no validation needed)

**There is no QUESTION category.** It used to absorb findings the validator couldn't resolve, which made uncertainty the author's problem instead of the reviewer's. Anything obtainable from the repository must be resolved in 6e or dropped.

The one exception, and it is narrow: information that genuinely lives only with the author or the product owner — "does a mid-edit refetch actually happen here?", "were these TranslationService keys created?", "was this endpoint meant to ship in this PR?". Those go in a short **Needs an answer** list, capped at three, and each one must state what you already checked so the author isn't asked to repeat your work. If you can answer it with a grep, grep it.

### Step 7: Present Review to User

Before posting to GitHub, show the full review:

Each finding leads with the defect in one line, then the replacement code, then the evidence that the replacement is right. Prose about the problem is worth less than the two lines that fix it.

```
## Review Summary: PR #1670 — "Add age field to profile card"

**Verdict:** Approve with improvements

### MUST FIX (1)

1. `src/components/ProfileCard.tsx:42` — `employeeData.managers` is nullable, so `.length` throws
   for any employee without a manager.

   ```tsx
   - {employeeData.managers.length > 0 && <ManagerList managers={employeeData.managers} />}
   + {employeeData.managers?.length ? <ManagerList managers={employeeData.managers} /> : null}
   ```
   Evidence: `ManagerResponse.managers` is `Manager[] | null` at `store/rtk-apis/service-b/service-bApi.ts:812`;
   the seed has 3 of 11 employees with no manager row.

### IMPROVEMENT (1)

1. `src/utils/date.ts:30` — Hand-rolled day comparison duplicates an existing helper.

   ```ts
   - if (startOfDay(new Date(plannedAt)) < startOfDay(new Date()))
   + if (isBeforeToday(plannedAt))
   ```
   Evidence: `isBeforeToday` at `utils/date.ts:214`, already used at 9 call sites; the raw
   version compares an instant against local midnight and misreports at negative offsets.
   Trade-off: none — the helper is strictly narrower.

### PRAISE (1)
1. `src/utils/date.ts:15` — Great use of `getDateWithoutTzConversion`

### Needs an answer (1)
1. Were the four new `billingProducts_*` keys created in TranslationService? They appear nowhere in the
   repo, which is expected since translations live in S3 — so this is the one thing I can't
   check from here.
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
- All SUGGESTION/IMPROVEMENT/PRAISE only → `"event": "APPROVE"`
- Any MUST FIX → `"event": "REQUEST_CHANGES"`
- `--no-approve` flag → `"event": "COMMENT"` (always)
- User chose "comments only" → `"event": "COMMENT"`

**Comment formatting:**
- Prefix each comment with its category in bold: `**MUST FIX**:`, `**SUGGESTION**:`, etc.
- Post the replacement code as a fenced diff or code block in the comment body. A proposal the author can copy is the point; a description of it is not.
- **IMPROVEMENT findings are shown locally but not posted by default.** They are unsolicited advice on someone else's work, which reads differently from a bug report. Offer them as an explicit choice when asking the user in Step 7: "Post improvements too?" Default no.
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
- **Ship proposals, not observations**: a finding without replacement code is not a finding. If you cannot write the fix, you have not understood the problem well enough to raise it — drop it. This is the single rule that separates a useful review from a list of things for someone else to think about.
- **Verify before asserting, and verify before proposing**: open the file, grep the call sites, read the library source, run the search that would disprove you. A claim that is internally consistent with the diff can still be wrong about the repository — and a confident wrong proposal costs the author more than silence. Name the artifact you read.
- **Never invent a follow-up ticket without scanning first**: before proposing that something be split into a new story, search for the other instances. If the diff is the only one, it belongs in the current story. If there are others, the count is the argument for the ticket.
- **Don't ask what you can look up**: questions are the reviewer's unfinished work handed to the author. Reserve them for what only the author or PO knows, and state what you already checked.
- **Be balanced**: include PRAISE — reviews shouldn't be all negative
- **Don't nitpick**: skip trivial formatting if auto-formatters exist
- **Check existing reviews**: don't duplicate feedback already given
- **Line numbers**: use the line numbers from the diff/patch, which correspond to the new file version. The GitHub API `line` parameter refers to the line in the diff hunk.
- **Full mode failures degrade gracefully**: if worktree creation fails, fall back to fast mode. If builds/tests fail to run (missing deps, etc.), note it but continue the review.
