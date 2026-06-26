---
name: tester-handoff
description: Generate a non-developer-friendly test guide for a PR or Jira ticket. Outputs a structured text file with self-testable visual checks, developer-required dev-tools checks, and non-testable items. Each scenario has a plain-language explanation, a clickable URL into the QA/accept environment, step-by-step instructions, expected behavior, and "what could be wrong". Use when handing off a PR to QA, writing test scenarios for a tester, preparing UAT instructions, or creating a "how to test" document to attach to Jira. Pulls QA environment URL + test user + customer ID from `~/.claude/dtf-config.json` (`qaEnvironment` section).
autoTrigger:
  - when user asks to write a test guide, tester handoff, QA handoff, or "how to test" doc
  - when user wants to give a non-developer tester clear test instructions for a PR
  - when user mentions sending test instructions to QA / a tester
globs:
  - "**/*"
---

# Tester Handoff — Non-Developer Test Guide Generator

Generate a structured, plain-language test guide for a PR or Jira ticket. The output is aimed at a **non-developer tester** — assume the reader does NOT understand "render", "state", "memo", "effect", "dep array", "cascade", "memoization". Use everyday words: "flicker", "blinks", "stays", "doesn't update", "is left over".

## Output

A plain-text file at the repo / worktree root:
- Default filename: `howtotest-<TICKET-ID>.txt` (e.g., `howtotest-PROJ-2357.txt`)
- If no ticket ID is resolvable, fall back to `howtotest-<branch-name>.txt`.

The file has **three parts** (always include all three, even if some are empty):

```
PART A — TESTS YOU CAN DO YOURSELF (visual, no developer needed)
PART B — TESTS THAT NEED A DEVELOPER (require DevTools, Network, Profiler)
PART C — NOT TESTABLE (information only)
```

Within each part, each test scenario uses this exact template:

```
─────────────────────────────────────────────
[ID]. [SHORT, NON-TECHNICAL TITLE]
─────────────────────────────────────────────

What this is about:
[1-2 sentences in plain language. NO jargon. Describe the user-visible
behavior, not the internal mechanism.]

URL to go to:
[Full URL from QA environment + customerId + path]

Steps:
1. [Concrete user action]
2. [Concrete user action]
3. ...

What should happen:
- [Concrete observable outcome]

What could be wrong:
- [Observable bug, e.g., "the field flickers", "the value stays
  from before", "the page doesn't update"]
```

Add a top header section with:
- Title with ticket ID + summary
- Login user (from config)
- A "general things to look out for" paragraph in plain language explaining what "flicker" / "stays from before" / "doesn't update" look like.

End with a **summary index** listing all scenarios with one-line titles per part.

## Workflow

### Step 1 — Resolve scope

Determine what to generate the guide for:
- If user provided a PR number → use that PR (`gh pr view <N>`)
- If user provided a Jira ticket ID → use that ticket (`acli jira workitem view <ID>`)
- If neither → use the current branch's PR if there is one, otherwise the branch's name + last few commits

Pull these data points:
- Ticket ID, summary, description (read `.dream-team/jira-ticket.md` if it exists, else `acli`)
- PR body (especially "How to Test", "Visual verification", "Behavioral notes")
- File diff (`gh pr view <N> --json files` or `git diff origin/main`)
- Existing Jira comments (read with `acli jira workitem comment list --key <ID> --json` — they often have prior test instructions to extend, not replace)

### Step 1.5 — Check skip conditions (avoid generating useless guides)

Before generating a full guide, check the PR diff. If ALL changed files match one of the categories below, **skip the full guide** and instead post a one-line Jira comment explaining why no tester walkthrough is needed.

| Category | Match rule | Jira comment to post instead |
|---|---|---|
| Backend-only | No files under `apps/web/src/**` changed | "Backend-only PR — verified via API tests and regression suite. No tester walkthrough needed." |
| Docs-only | Only `*.md`, `docs/**`, `*.txt`, `README*` changed | "Documentation update — no functional test needed." |
| Deps-only | Only `package.json`, `package-lock.json`, `*.csproj`, `Directory.Packages.props` changed | "Dependency bump — covered by CI build + existing test suite." |
| Test-only | Only `*.test.ts*`, `*.spec.ts*`, `*Test.cs`, `*IntegrationTests.cs` changed | "Test-only change — covered by the test suite itself." |
| i18n-only | Only translation/TranslationService files (`*.json` under translation paths) | "Translation update — verify in the target language(s) at the affected pages." |

Localize the comment to the configured `qaEnvironment.defaultLanguage`.

If the PR has a mix (e.g., backend + some frontend), DO generate the guide — but scope only to the frontend-visible surface.

If the PR is **manually invoked** (user said "write a test guide" explicitly), do NOT auto-skip — the user has overridden the heuristic.

### Step 2 — Load QA environment config (SILENT)

Read `~/.claude/dtf-config.json`. Look for a `qaEnvironment` block:

```json
{
  "qaEnvironment": {
    "baseUrl": "https://polaris-accept.repo.se",
    "testUser": "Gunner",
    "customerId": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d"
  }
}
```

**Do NOT prompt the user mid-flow.** This skill is typically invoked automatically by DTF — interrupting with config questions breaks the flow.

If the block is missing or incomplete:
- Fill missing fields with `<TODO: set in ~/.claude/dtf-config.json qaEnvironment.<field>>` placeholders in URLs
- Add a soft warning to the TOP of the generated file:
  ```
  ⚠️  QA environment config is incomplete in ~/.claude/dtf-config.json.
  URLs contain placeholders. To fix permanently, add a `qaEnvironment` block:
    "qaEnvironment": {
      "baseUrl": "https://your-qa-env.example.com",
      "testUser": "TestUser",
      "customerId": "<your-test-customer-uuid>"
    }
  ```
- Continue and write the file anyway — placeholder URLs are still useful as a structural reference.

URL template: `<baseUrl>/<customerId>/<route>` (and `<baseUrl>/<public-route>` for pre-login screens like `/login/oneTimePass`).

### Step 3 — Language (silent default)

Read `qaEnvironment.defaultLanguage` from `~/.claude/dtf-config.json`. Default: **English**.

**Do NOT prompt mid-flow.** If the user explicitly asks for a specific language ("write the test guide in Swedish"), honor that — otherwise use the configured default. To change the default permanently, the user edits `~/.claude/dtf-config.json` `qaEnvironment.defaultLanguage`.

All scenario text — titles, "What this is about", steps, expected/possible bugs — is generated in the chosen language. The structural labels (PART A/B/C, scenario template field names) are also localized: e.g., Swedish uses "Vad detta handlar om", "Steg-för-steg", "Vad ska hända", "Vad kan vara fel".

### Step 4 — Classify changes

For each significant change in the PR (file group / hook / component), decide which part it belongs in:

**PART A — Tester can verify themselves (visual)**:
- The change has a user-visible surface (a page, modal, popover, dropdown, form, button, etc.).
- The bug it prevents is observable without DevTools (a flicker, lingering value, broken navigation, data not refreshing).
- The tester can reach the surface in the QA environment with the configured test user.

**PART B — Needs a developer alongside**:
- The change is observable only via DevTools (Network panel, React DevTools Profiler, console).
- The change is a "no extra re-renders" / "no duplicate network calls" type fix.
- The behavior depends on timing or polling that's hard to confirm visually.

**PART C — Not testable**:
- Dead code (no consumers).
- Requires data setup that isn't in the QA environment.
- Behavior change that's intentional and could be misreported as a bug (document so tester doesn't flag it).

When in doubt, prefer Part A with a clear "What could be wrong" line — the tester can flag anything ambiguous.

### Step 5 — Generate scenarios

For each change in Part A and Part B, generate a scenario using the template. Rules:

1. **Plain language.** Don't say "the useEffect was converted to during-render adjustment". Say "the popup remembered what you typed last time — now it doesn't, which is the fix".
2. **Concrete URLs.** Use the configured baseUrl + customerId. For routes that need a userId / reportId placeholder, show `<userId>` literally and explain how to find one (e.g., "click on a user in the Users list").
3. **Numbered steps.** Each step is one click / one input / one wait. No combined "go to X and then do Y and Z" steps — split into separate lines.
4. **Always include "What could be wrong"** — the tester needs to know what to flag. Use words from the everyday glossary below.
5. **No internal references.** Don't say "useMemo was added on line 30" or "the dep array was stabilized". Say "the list won't blink when you switch companies".

### Everyday glossary (use these words instead of jargon)

| Don't write | Write instead |
|---|---|
| re-render / render | "updates", "refreshes", "redraws" |
| state | "the value", "what's selected", "what you picked" |
| effect / useEffect | (don't mention) |
| memo / memoize | (don't mention) |
| cascade | "blinks rapidly", "updates many times in a row" |
| flicker | "flicker", "blinks", "flashes" (these are OK words) |
| stale | "old / left-over value" |
| dep / dependency | (don't mention) |
| prop | "value coming from somewhere else" |
| ref | (don't mention) |
| during-render | (don't mention) |

### Step 6 — Write the file

Write to `<repo-root>/howtotest-<TICKET-ID>.txt`. If the user is in a worktree (e.g., `~/Documents/<TICKET-ID>`), use the worktree root. Otherwise use the current working directory.

Use the section dividers exactly as in the template (`═══` for major sections, `───` for scenarios) so the file is scannable.

### Step 7 — Offer Jira attach

After writing the file, **ask** if the user wants to attach it to the related Jira ticket. If yes, upload via the Atlassian REST API. **`acli` cannot upload attachments** (only `attachment list`/`delete`), so the REST call is the only path.

**REQUIRED first: warm up the token.** The `access_token` in the keychain expires, and a stale one returns **401 Unauthorized** on the attachment POST. Running any `acli` command first forces acli to refresh the keychain token — do the `acli … view` line BELOW immediately before extracting, never skip it. (Confirmed NOVA-3062: skipping the warm-up → 401; warming up → 200.) If the POST still 401s after a warm-up, the acli session itself is expired — tell the user to re-auth acli, and fall back to posting the guide's 3-part summary as an inline Jira comment (which always works via `acli jira workitem comment create`).

```bash
# Token from ACLI keychain (same pattern as ~/.claude/scripts/jira-download-attachments.sh)
# The view call is NOT optional — it refreshes the keychain token so the POST won't 401.
acli jira workitem view <TICKET> --fields summary > /dev/null 2>&1
ACCESS_TOKEN=$(security find-generic-password -s "acli" -w 2>/dev/null | python3 -c "
import sys, base64, gzip, json
d = sys.stdin.read().strip()
d = d[len('go-keyring-base64:'):]
print(json.loads(gzip.decompress(base64.b64decode(d)))['access_token'])
")
CLOUD_ID="4f617dfc-e4b4-4019-826c-6d9df112d610"
curl -s -X POST "https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3/issue/<TICKET>/attachments" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Atlassian-Token: no-check" \
  -F "file=@<path-to-file>"
```

If attachment succeeds, also offer to **add a Jira comment** that points to the file:

> "Testguide bifogad som `howtotest-<TICKET-ID>.txt` — innehåller [N] tester du kan göra själv (Del A), [M] tester som behöver utvecklare bredvid (Del B), och [K] punkter som inte är testbara (Del C)."

(Localize to the chosen language.)

### Step 8 — Verify file is readable

After writing, spot-check the file by reading the first ~30 lines and the summary index at the end. Confirm the language is consistent and no jargon leaked through (search for "render", "useEffect", "memo", "state" in the output and fix any that slipped in).

## Examples of plain-language phrasings

### Bad (developer talk)
> "The `useMemo` wrap on `collectionsResponse?.data ?? []` stabilizes the reference so downstream `useMemo`s and `useEffect`s don't re-fire on every render."

### Good (tester language)
> "When you switch company in the dropdown, the list of companies shouldn't blink or close unexpectedly. Updates should be smooth."

---

### Bad
> "Convert the `setSelectedTagsByKey([])` setState-in-effect to an adjust-during-render branch guarded by a previous-companyIds state to avoid the cascade."

### Good
> "When you switch from one company to several companies in the filter, the tags you picked should clear automatically (tags only make sense for one company at a time)."

## Common pitfalls

1. **Skipping the "What could be wrong" line.** This is the single most important line — without it the tester doesn't know what to flag.
2. **Using "React" or "React Compiler" in tester-facing text.** Never — the tester doesn't care which framework.
3. **Combining multiple checks into one step.** Split: each step is one action.
4. **Long sentences in "What this is about".** Two short sentences max. The tester scans, doesn't read deeply.
5. **Forgetting Part C.** Items that aren't testable but could be mistaken for a bug (e.g., intentional slower UX) belong in Part C so the tester doesn't open false tickets.

## Quality bar

The output should be readable by a non-developer in 5 minutes. After reading, they should:
- Know exactly which URLs to visit
- Know step-by-step what to do
- Know what a passing test looks like
- Know which scenarios to skip / flag for a developer
- Not need to ask the author follow-up questions to start testing
