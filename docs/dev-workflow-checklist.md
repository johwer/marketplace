# Dev Workflow Checklist — Shared Quality Gates

This checklist applies to **all dev sessions**: Dream Team, lite mode, and solo Claude sessions.
Every section marked **HARD GATE** is a blocking requirement — do NOT proceed past it until satisfied.

> **⚠️ Maintainer note — coupled files:**
> This checklist shares tooling and process with `~/.claude/commands/my-dream-team.md`.
> When you change **visual verification**, **PR lifecycle**, **quality gates**, or **tool choices** here,
> you MUST update the Dream Team command too (and vice versa).
> - `dev-workflow-checklist.md` = quality gates (what must be true before proceeding)
> - `my-dream-team.md` = orchestration (who does what, when)
>
> After editing either file, run: `bash ~/.claude/scripts/sync-config.sh`

---

## Section 1: Visual Verification — HARD GATE

Applies to all tickets with UI changes. Skip for backend-only/infra-only tickets.

**The rule (canonical — keep in sync with memory `feedback_dtf_visual_verification_contradiction`, `feedback_real_browser_verification_mandatory`, `feedback_screenshots_user_visible_paths`):** visual verification means **driving the LIVE app in a real browser via `playwright-cli`** and saving screenshots to **`~/Downloads/<TICKET_ID>/`**. It does NOT mean writing committed Playwright e2e specs or `toHaveScreenshot` baselines — those are the rare exception, only when the user explicitly asks for a visual-regression test.

### Requirements

- **Drive the real running app** with `playwright-cli -s=<agent>` (worktree dev server on port 31xx): exercise the actual change (click/select/type), and check **network + console**, not just the DOM. The headless test runner passes assertions while missing wrong/failed requests, stale ids, console errors, and ErrorBoundary crashes — the live browser is what catches those.
- **Screenshots → `~/Downloads/<TICKET_ID>/`** (user-visible folder; on Swedish macOS shown as "Hämtade filer"). One per relevant state. **NEVER** the repo, **NEVER** `/tmp`. The user drag-drops them into the PR description; nothing is committed.
- **New component → add a Cosmos fixture** (`*.fixture.tsx`, run via `npx cosmos --config cosmos.worktree.config.json`) for component states — preferred over an e2e spec. Add a unit test too if it has interactive/conditional logic.
- **No committed screenshots or e2e baselines by default.** No `page.screenshot()` artifacts in `src/**/__screenshots__/`, no `toHaveScreenshot` baselines/specs unless the user explicitly requested a regression test.
- **No GIF/video.** Only record video if the user explicitly requests it (and then `playwright-cli video`, never `gif_creator`).

### Verification

```bash
# 1. Screenshots exist in the user-visible folder (lead has personally seen the rendered output):
ls ~/Downloads/<TICKET_ID>/*.png 2>/dev/null

# 2. NO screenshots / e2e baselines committed to the repo — this must return NOTHING:
git diff --name-only origin/main | grep -E 'src/.*__screenshots__/.*\.png|tests/e2e/.*-snapshots/.*\.png'
```

If check 1 finds nothing: **DO NOT push** — drive the live app and capture the screenshots first. A verbal "verified in browser" or a dev's claim is NOT sufficient; the lead must have driven the live app itself (real-browser re-verification is the lead's gate).
If check 2 finds anything: **remove those files** — screenshots go to `~/Downloads`, not the repo.

### Real-browser verification — Playwright CLI (the method)

```bash
# 1. Open the live worktree app with a named session
playwright-cli -s=<agent-name> open http://localhost:<VITE_DEV_PORT>/<path> --headed

# 2. Drive the actual change (refs from snapshot; eval reads live DOM/state)
playwright-cli -s=<agent-name> snapshot
playwright-cli -s=<agent-name> click e5

# 3. Check what headless can't catch
playwright-cli -s=<agent-name> network          # requests route correctly, no new non-2xx
playwright-cli -s=<agent-name> console error    # no JS/React errors

# 4. Capture evidence to the user-visible folder (NEVER the repo)
mkdir -p ~/Downloads/<TICKET_ID>
playwright-cli -s=<agent-name> screenshot --filename=~/Downloads/<TICKET_ID>/<state>.png

# 5. Close session
playwright-cli -s=<agent-name> close
```

Each agent uses their own named session (`-s=ingrid`, `-s=lena`, etc.) — no queue needed.

**Multi-worktree parallel testing**: S3 translations work on all 3xxx ports (CORS: `http://localhost:3*`). Each worktree's Vite port (3100-3199 from `allocate-ports.sh`) gets full translation support — multiple worktrees can run Playwright simultaneously without port conflicts or missing translations.

Full docs: `~/.claude/skills/playwright-cli/SKILL.md`

---

## Section 2: i18n / TranslationService — HARD GATE

Applies to all tickets that add or modify user-facing text.

### Rules

- Use **bare `t("key")` only** — NEVER use `defaultValue`
- Before creating new keys, **grep the codebase** for existing keys to avoid duplicates and casing mismatches (e.g., `common_logout` not `common_logOut`)
- Key naming pattern: `{page}_{section}_{element}` (e.g., `employeeCard_service-aForm_submitButton`)
- Dynamic keys: add pattern to `scripts/lokalise_whitelist.json`

### Workflow

1. Implement all UI text using `t("key")` references
2. Grep your changed files for all `t(` calls — collect every key
3. For each new key, create it in TranslationService via the API with **all 5 languages** (en, sv, da, no, fi):
   ```bash
   TRANSLATION_SERVICE_KEY=$(grep TRANSLATION_SERVICE_API_KEY apps/web/.env.local | cut -d= -f2)
   curl -X POST "https://api.lokalise.com/api2/projects/3907704568ac1345097c75.30587214/keys" \
     -H "X-Api-Token: $TRANSLATION_SERVICE_KEY" \
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

**Completion is blocked** until TranslationService API calls succeed for every new key. If the API is unavailable, note it in the completion message and flag for the team lead.

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
4. **Tester handoff (auto, before going ready)**: When the user confirms "ship it", invoke the `tester-handoff` skill BEFORE marking the PR ready. The skill auto-skips for backend-only / docs / deps / test-only / i18n-only PRs (posts a short Jira comment instead). For everything else, it generates `howtotest-<TICKET-ID>.txt`, attaches it to Jira, and posts a pointer comment. This is mandatory in both lite and team mode — applies to every user-facing change.
5. **User confirms ready**: Only when user says "Done — ship it":
   - Mark PR ready: `gh pr ready <PR_NUMBER>`
   - **Reviewers are auto-assigned by `.github/CODEOWNERS` on ready — do NOT manually assign.** Confirm who was picked: `gh pr view <PR_NUMBER> --json reviewRequests --jq '.reviewRequests[]?.login'` and report to the user.
6. **Never manually assign reviewers from `reviewers.json` in the flow.** CODEOWNERS handles it. The opt-in [`/reviewers`](#) command exists only for explicitly adding *extra* reviewers beyond CODEOWNERS, when the user asks.

### Reviewer Category Mapping (for the opt-in `/reviewers` command only — NOT the default flow)

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

## Section 5.5: De-Sloppify Pass

Before committing, review all changed files for over-engineering and defensive bloat. This catches patterns that agents naturally introduce.

### What to Look For

| Pattern | Example | Fix |
|---------|---------|-----|
| Unnecessary null checks | `if (x !== null)` on a non-nullable prop | Remove the check |
| Over-engineered error handling | try/catch around code that can't throw | Remove the try/catch |
| Redundant tests | Tests duplicating others with trivial variations | Delete the redundant test |
| Unnecessary comments | `// Set the name` above `setName(value)` | Delete the comment |
| Dead code | Unused imports, unreachable branches | Remove them |
| Premature abstractions | Helper functions used exactly once | Inline the code |
| Unnecessary type assertions | `as SomeType` where TS can infer | Remove the assertion |
| Verbose patterns | `if (x === true)` instead of `if (x)` | Simplify |

### How to Apply

- Quick scan — spend max 5 minutes on this pass
- Only fix clear-cut slop, don't refactor working code
- Run `dotnet build` / `npx tsc --noEmit` after cleanup to verify nothing broke
- If you find 0 issues, great — move on

### In Lite Mode

The team lead does this directly. In full Dream Team mode, the team lead does it in Phase 4.9 (after visual verification, before commit).

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
| 2 | **Auth/Authz** | Yes | — | Missing `[Authorize]` on new endpoints, broken access control (user A accessing user B's data), privilege escalation, wrong permission level (read vs write), **new `UserAction` without backend controller enforcement** (every new `UserAction` that gates data visibility MUST have a `CanDoActionOnUser` check in the relevant controller — frontend-only gating is A01 Broken Access Control) |
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

## Section 7.5: Context Management

### Strategic Compaction

Long sessions degrade output quality. Follow these rules:

**GOOD breakpoints (compact here):**
- After research/exploration completes — before writing code
- After a milestone — feature done, tests passing
- After a debugging session — bug found and fixed
- After agent results are absorbed — key points noted
- Phase transitions — between Phase 1→2, 3→4, 4→5

**BAD times (NEVER compact here):**
- Mid-implementation — you're editing and iterating
- During code review — need full diff context
- While debugging — need error context and hypotheses
- Between related file edits — finish all dependent files first

**Context thresholds:**
- < 30%: No action needed
- 50-70%: Look for the next good breakpoint
- \> 70%: Compact at the VERY NEXT good breakpoint
- \> 85%: Compact NOW — quality degradation is worse than losing context

### Context Modes

Switch mindset based on current activity:
- **Dev mode** — "Write code first, explain after." Priorities: working → right → clean.
- **Review mode** — "Read thoroughly, prioritize by severity." Categorize: MUST FIX / SUGGESTION / QUESTION / PRAISE.
- **Research mode** — "Read widely before concluding." Don't write code until understanding is clear.

Activate by saying "dev mode" / "review mode" / "research mode". Auto-activates for relevant commands.

---

## Section 8: File Management

### Verification Artifacts — Storage

Visual-verification screenshots are **evidence, not repo files** — they live in a user-visible folder, never the repo:
```
~/Downloads/<TICKET_ID>/
  changelog-notification-subscriptions.png   ← real-browser captures
  changelog-external-receivers.png
```
The user drag-drops these into the PR description. Nothing is committed to the repo.

**New component → a Cosmos fixture** documents component states (run via `npx cosmos --config cosmos.worktree.config.json`):
```
apps/web/src/.../<Component>.fixture.tsx
```

**No committed screenshots / e2e baselines by default**, and **no GIF/video**. A committed `toHaveScreenshot` regression test (in `apps/web/tests/e2e/` with baselines in `__snapshots__/`) is the rare exception — only when the user explicitly asks for one.

### File Naming

| File | Location | Pattern | Example |
|------|----------|---------|---------|
| Visual-verification screenshot | `~/Downloads/<TICKET_ID>/` | `<state>.png` | `changelog-external-receivers.png` |
| Cosmos fixture (new component) | next to the component | `<Component>.fixture.tsx` | `Callout.fixture.tsx` |
| Jira attachments | `~/Downloads/` | Original filename from Jira | `image-20260227-140735.png` |

### Download Location

- macOS path: `~/Downloads/`
- On Swedish macOS, Finder shows this as **"Hämtade filer"** but the filesystem path is still `~/Downloads/`
- Visual-verification screenshots and Jira attachments live here

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
| 2 | **Real-browser visual verification done; screenshots in `~/Downloads/<TICKET_ID>/`; none committed** (if UI changes) | `ls ~/Downloads/<TICKET_ID>/*.png` finds files AND `git diff --name-only origin/main \| grep -E 'src/.*__screenshots__/.*\.png\|tests/e2e/.*-snapshots/.*\.png'` returns nothing (see Section 1) |
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
