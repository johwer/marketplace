# Dev Workflow Checklist — Shared Quality Gates

This checklist applies to **all dev sessions**: Dream Team, lite mode, and solo Claude sessions.
Every section marked **HARD GATE** is a blocking requirement — do NOT proceed past it until satisfied.

---

## Section 1: Visual Verification — HARD GATE

Applies to all tickets with UI changes. Skip for backend-only/infra-only tickets.

### Requirements

- **Before** and **after** GIFs/screenshots MUST exist as files on disk
- File naming: `<TICKET_ID>-before.gif`, `<TICKET_ID>-after.gif`
- Storage location: `~/Downloads/` (see Section 6 for macOS locale notes)

### Verification

```bash
# This MUST succeed before pushing
ls ~/Downloads/<TICKET_ID>-after.gif
```

If the file does not exist on disk:
1. **DO NOT push.** Record visual evidence first.
2. A verbal claim of "verified in browser" is NOT sufficient.
3. If the agent claims "verified" but the file doesn't exist after 3 attempts, escalate to user.

### Recording Steps

1. Get Chrome access via the Chrome Browser Queue (`~/.claude/scripts/chrome-queue.sh`)
2. Start Vite dev server on port 3000: `VITE_DEV_PORT=3000 npm start` — the Chrome plugin connects to port 3000. The queue ensures only one workspace uses it at a time.
3. Navigate to the affected page on `https://localhost:3000/...`
4. Record GIF: `gif_creator action=start_recording` → screenshots → `action=stop_recording` → `action=export filename="<TICKET_ID>-after.gif" download=true`
5. Verify file exists on disk with `ls`
6. Release Chrome

---

## Section 2: i18n / Lokalise — HARD GATE

Applies to all tickets that add or modify user-facing text.

### Rules

- Use **bare `t("key")` only** — NEVER use `defaultValue`
- Before creating new keys, **grep the codebase** for existing keys to avoid duplicates and casing mismatches (e.g., `common_logout` not `common_logOut`)
- Key naming pattern: `{page}_{section}_{element}` (e.g., `employeeCard_absenceForm_submitButton`)
- Dynamic keys: add pattern to `scripts/lokalise_whitelist.json`

### Workflow

1. Implement all UI text using `t("key")` references
2. Grep your changed files for all `t(` calls — collect every key
3. For each new key, create it in Lokalise via the API with **all 5 languages** (en, sv, da, no, fi):
   ```bash
   LOKALISE_KEY=$(grep LOKALISE_API_KEY apps/web/.env.local | cut -d= -f2)
   curl -X POST "https://api.lokalise.com/api2/projects/3907704568ac1345097c75.30587214/keys" \
     -H "X-Api-Token: $LOKALISE_KEY" \
     -H "Content-Type: application/json" \
     -d '{ "keys": [{ "key_name": "your_key", "platforms": ["web"], "translations": [
       {"language_iso": "en", "translation": "English text"},
       {"language_iso": "sv", "translation": "Svensk text"},
       {"language_iso": "da", "translation": "Dansk tekst"},
       {"language_iso": "no", "translation": "Norsk tekst"},
       {"language_iso": "fi", "translation": "Suomalainen teksti"}
     ]}]}'
   ```
4. Verify each API call succeeds (HTTP 200)

### Gate Check

**Completion is blocked** until Lokalise API calls succeed for every new key. If the API is unavailable, note it in the completion message and flag for the team lead.

Reference: `docs/INTERNATIONALIZATION.md`

---

## Section 3: PR Review Comment Resolution — HARD GATE

### Triage — Before Acting on a Comment

Not every comment requires a code change. Evaluate before implementing:

1. **Is the reviewer correct?** Check the code — they may lack context you have
2. **Is it a question or a change request?** Questions need answers, not code changes
3. **Is it an AI bot?** Copilot/Gemini suggestions are often wrong — verify independently
4. **Would the change introduce risk?** (e.g., squashing migrations already deployed to staging/prod)
5. **Does it contradict repo conventions?** Push back with a reference to the relevant doc

**If you disagree:** reply with your reasoning and let the reviewer respond. Do not resolve — leave the thread open for discussion.
**If you agree:** implement the fix, then reply and resolve.

### After Every Fix Commit

1. **Reply** to the comment explaining the fix
2. **Resolve** the conversation thread via GraphQL API:

```bash
# Get all unresolved thread IDs
gh api graphql -f query='{ repository(owner: "<OWNER>", name: "<REPO>") { pullRequest(number: <PR_NUMBER>) { reviewThreads(first: 50) { nodes { id isResolved comments(first: 1) { nodes { body author { login } } } } } } } }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | .id'

# Resolve each thread
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<THREAD_ID>"}) { thread { isResolved } } }'
```

### Gate Check

Before proceeding to the next step (CI polling, marking ready, etc.):
- Query unresolved thread count — **must be 0**
- DO NOT proceed with unresolved threads

---

## Section 4: PR Lifecycle

### Draft → Ready → Reviewers

1. **Phase 1.5**: PR created as **DRAFT** (`gh pr create --draft`)
2. **AI review + CI**: PR stays as draft throughout
3. **User review**: After AI review and CI are green, notify the user. PR is still a draft.
4. **User confirms**: Only when user says "Done — assign reviewers & ship it":
   - Mark PR ready: `gh pr ready <PR_NUMBER>`
   - Assign reviewers from `~/.claude/reviewers.json` based on scope category
   - `gh pr edit <PR_NUMBER> --add-reviewer "user1,user2"`
5. **Never auto-assign reviewers** before user confirmation

### Reviewer Category Mapping

| Scope | Category |
|-------|----------|
| frontend-only | `frontend` |
| backend-only | `backend` |
| full-stack | `fullstack` |
| infra-only | `infra` |
| data | `data` |

---

## Section 5: Testing — Empty State & API Actions

### Empty State Tests

When writing tests for endpoints or UI that read/write data, always include a test case for **empty state** (no existing records). If the endpoint creates or updates, test both:
- Entity exists → update
- Entity **doesn't exist** → create or handle gracefully (not 400/500)

This applies to both backend unit tests and frontend integration points.

### API Action Verification

If you added or changed an API integration, **verify the action** — not just the page render. Click the button that triggers the API call (save, delete, submit) and confirm it succeeds. Screenshot should show the **result of the action**, not just the form.

---

## Section 6: Pre-Push Quality Gates

Before the first `git push` on any branch:

### Deterministic Quality Gate Script

Run the quality gate script instead of manual commands — it handles formatting, linting, type checks, and builds deterministically (no LLM tokens burned):

```bash
bash ~/.claude/scripts/quality-gate.sh <worktree-path>
```

Auto-detects backend/frontend from changed files. Auto-fixes formatting (CSharpier, Prettier, ESLint). Reports failures. Must exit 0 before pushing.

### Build Verification (if not using the script)

```bash
# Backend (if changed)
cd <worktree> && dotnet build services/<ServiceName>/<ServiceName>.sln 2>&1 | tail -5

# Frontend (if changed)
cd <worktree>/apps/web && npx tsc --noEmit 2>&1 | tail -5
```

Compare with baseline captured at start of session. If baseline was green and now red, there's a regression — fix before pushing.

### Formatting (if not using the script)

- **C#**: `dotnet csharpier .` on changed files
- **TypeScript/React**: `npx prettier --write .` and `npx eslint --fix .` on changed files

### CI Iteration Cap — 2 Rounds Max

After pushing, if CI fails:
- **Round 1**: Fix the issue, commit, push, re-poll CI
- **Round 2**: If CI fails again, fix and push one more time
- **After Round 2**: If CI still fails, **stop and escalate to the user**. Do not attempt a third round — diminishing returns beyond 2 attempts. Report what failed and what was tried.

### Merge Conflict Pre-Check

```bash
git fetch origin main
git diff origin/main...HEAD --name-only
```

Hot files that often conflict: `AppRoutes.tsx`, `EmployeeCardTabs.tsx`. If your branch touches these AND main has changed them, rebase first:

```bash
git rebase origin/main
```

### Rebase Strategy

- **Before first push**: Always rebase on `origin/main` (mandatory)
- **During review cycles**: Rebase before each subsequent push if multiple rounds
- **Before marking ready**: Final rebase to ensure clean merge

---

## Section 7: Security Scan — HARD GATE

Applies to every PR before marking ready. The scan scope is determined by which file types were changed.

### Detect Scope

```bash
# Check what changed
CHANGED=$(git diff --name-only origin/main)
HAS_BACKEND=$(echo "$CHANGED" | grep -c '\.cs$' || true)
HAS_FRONTEND=$(echo "$CHANGED" | grep -c '\.\(ts\|tsx\)$' || true)
```

### Categories

Run the applicable categories based on changed file types:

| # | Category | Backend (.cs) | Frontend (.ts/.tsx) | What to look for |
|---|----------|:---:|:---:|------------------|
| 1 | **Injection** | Yes | — | SQL injection (raw queries, string concatenation in EF), command injection (user input in `Process.Start`/Bash) |
| 2 | **Auth/Authz** | Yes | — | Missing `[Authorize]` on new endpoints, broken access control (user A accessing user B's data), privilege escalation, wrong permission level (read vs write) |
| 3 | **Data exposure** | Yes | — | Sensitive fields (SSN, email, salary) in API responses that shouldn't have them, PII in log statements, secrets/tokens committed to git |
| 4 | **Path traversal** | Yes | — | User-controlled file paths without sanitization (`../../../etc/passwd` patterns) |
| 5 | **Hardcoded secrets** | Yes | — | API keys, connection strings, passwords, tokens in source code (should be in env/config) |
| 6 | **Insecure defaults** | Yes | — | CORS set to `*`, missing HTTPS enforcement, overly permissive RBAC roles |
| 7 | **XSS** | — | Yes | Unsanitized user input rendered via `dangerouslySetInnerHTML` or unescaped output |

**Summary:**
- **Backend files changed** → run categories 1-6
- **Frontend files changed** → run category 7 (XSS)
- **Both changed** → run all 7

### Gate Check

- Any issue found = **MUST FIX** before marking PR ready
- In **full mode**: Maya runs this scan (categories are in her spawn prompt)
- In **lite mode**: The team lead runs it directly — same categories, same standard
- Document findings with `file:line` references

---

## Section 8: File Management

### Download Location

- macOS path: `~/Downloads/`
- On Swedish macOS, Finder shows this as **"Hämtade filer"** but the filesystem path is still `~/Downloads/`
- All screenshots, GIFs, and downloaded attachments go here

### File Naming

| File | Pattern | Example |
|------|---------|---------|
| Before GIF | `<TICKET_ID>-before.gif` | `PLRS-1831-before.gif` |
| After GIF | `<TICKET_ID>-after.gif` | `PLRS-1831-after.gif` |
| Jira attachments | Original filename from Jira | `image-20260227-140735.png` |

### Jira Attachments

- **Never use curl/wget** for Jira attachments (401 Unauthorized)
- Open in Chrome for authenticated download: `open -a "Google Chrome" "<URL>"`
- Or navigate to the ticket page in Chrome, click the attachment, and use the download button

---

## Section 9: Completion Gate — HARD GATE

Before transitioning a ticket to Done (Phase 7), **every item below must be confirmed**. This is the final quality gate — do NOT skip any item.

### Checklist

| # | Item | How to verify |
|---|------|---------------|
| 1 | **All PR review comments resolved** | `gh api graphql` query returns 0 unresolved threads (see Section 3) |
| 2 | **Screenshots/GIFs on disk** (if UI changes) | `ls ~/Downloads/<TICKET_ID>-after.gif` succeeds (see Section 1) |
| 3 | **Retrospective completed** | Phase 6.75 ran, learnings saved to `.dream-team/journal/` and memory |
| 4 | **Jira completion comment posted** | `acli jira workitem comment create` succeeded with PR link + summary |
| 5 | **CI is green** | Last push has all checks passing |
| 6 | **PR description is complete** | Summary, How to Test, and any screenshots are in the PR body |

### Jira Completion Comment

Post a comment to the Jira ticket summarizing what was done:

```bash
# Get ticket creator info
CREATOR_NAME=$(acli jira workitem view "<TICKET_ID>" --json --fields "creator" 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['fields']['creator']['displayName'])" 2>/dev/null || echo "")
CREATOR_ID=$(acli jira workitem view "<TICKET_ID>" --json --fields "creator" 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['fields']['creator']['accountId'])" 2>/dev/null || echo "")

# Post comment — @mention creator only if different from assignee
acli jira workitem comment create --key "<TICKET_ID>" \
  --body "Implementation complete. PR: <PR_URL>

Summary: <1-2 sentence description>

[~accountId:$CREATOR_ID] — ready for your review."
```

**Rules:**
- Always include the PR URL
- Keep summary to 1-2 sentences (what was done, not how)
- Only @mention the creator if they are NOT the assignee (avoid self-pinging)
- If the comment fails, note it in completion message but don't block

### Enforcement

This gate runs as **Phase 7 Step 1** in `/my-dream-team`. The team lead must confirm each item before proceeding to Jira transition and agent shutdown.
