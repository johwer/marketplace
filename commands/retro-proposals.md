---
context: fork
---

# Retro Proposals — Analyze Learnings & Route Improvements

ultrathink — this task requires deep reasoning to correctly classify learnings and route them to the right destination without duplicates.

Analyze accumulated Dream Team session data (retro learnings, history, journals) to identify patterns, flag problems, and propose concrete improvements. Routes learnings to the correct destination files — agent prompts, repo docs, or personal config.

> **Renamed from `/team-review`.** This command is part of the [Learning System](../docs/learning-system.md) alongside `/scrape-pr-history` and `/pr-insights`.

## Data Sources

Read these files (skip any that don't exist yet):

1. **Session history**: Look for `dream-team-history.json` in your project memory directory (`~/.claude/projects/*/memory/`)
   - Team sizing decisions and verdicts (good / over-spawned / under-spawned)
   - Complexity ratings, review rounds, must-fix counts
   - Journal highlights from each session
   - Achievement distribution

2. **Retro learnings**: Look for `dream-team-learnings.md` in the same project memory directory
   - Applied and deferred command file changes per session
   - Doc gaps found
   - Process notes

3. **Current command file**: `~/.claude/commands/my-dream-team.md`
   - To cross-reference whether past learnings have been addressed

## Analysis

If there are fewer than 2 sessions recorded, tell the user there isn't enough data yet and show what data will be collected after more sessions.

Otherwise, analyze across all sessions and produce a report:

```
## Dream Team Health Report

### Sessions Analyzed
[N sessions from DATE to DATE]

### Team Sizing Patterns
- Average team size: [N agents]
- Over-spawned: [N times] — [pattern description]
- Under-spawned: [N times] — [pattern description]
- **Recommendation**: [e.g., "Amara tends to over-spawn for frontend-only tickets — consider adding a rule to cap at 1 frontend dev for tickets under medium complexity"]

### Recurring Instruction Gaps
[Group journal highlights by category. If the same issue appears 2+ times, flag it.]
- **Repeated issue**: [description] — appeared in [N] sessions
- **Proposed fix**: [specific change to agent prompt in my-dream-team.md]

### Communication & Coordination
- Average review rounds: [N]
- Sessions with blocked agents: [N]
- Communication friction patterns: [from journal highlights]
- **Recommendation**: [e.g., "Kenji frequently waits for API contract details — consider having Amara provide a more detailed contract template"]

### Convention & Doc Gaps
[Recurring doc issues from retro learnings]
- [doc file]: [issue] — reported [N] times
- **Action**: [fix the doc / update agent instructions / add to conventions summary]

### Deferred Changes
[List changes from past retros that were saved but never applied]
- From [date] session: [change description]
- **Still relevant?** [yes/no based on current command file]

### Achievement Trends
- Most common: [achievement] ([N] times)
- Rarest: [achievement] ([N] times)
- Agents with no achievements yet: [names]

### Overall Health Score
Rate the team on these dimensions (1-5):
- **Instruction quality**: Are agent prompts giving them what they need?
- **Team sizing accuracy**: Is Amara calibrating well?
- **Communication flow**: Are agents coordinating without friction?
- **Review efficiency**: Are reviews catching real issues without excessive rounds?
- **Context efficiency**: Are agents staying within context limits?
```

## Learning Router

After the health report, route deferred learnings to the right destination files. This is the key value of `/retro-proposals` — learnings don't just sit in a markdown file, they get applied where they'll actually help.

### Destination Registry

| ID | Destination | Path | Scope |
|----|-------------|------|-------|
| `dream-team` | Dream Team command | `~/.claude/commands/my-dream-team.md` | Agent prompts, phases, process |
| `agent:<name>` | Standalone agent | `~/.claude/agents/<name>.md` | Agent behavior outside Dream Team |
| `skill:<name>` | Skill/command | `~/.claude/commands/<name>.md` | Skill-specific checklist or workflow |
| `project-claude` | Project CLAUDE.md | `<monorepo>/CLAUDE.md` | Monorepo quick-start info only (NOT conventions — use repo-docs for those) |
| `agents-md:<path>` | Repo AGENTS.md | `<monorepo>/<path>` | Agent-specific operational gotchas only (commands, auth, db names, ports) |
| `global-claude` | Global CLAUDE.md | `~/.claude/CLAUDE.md` | Every Claude session everywhere |
| `repo-docs` | Repo docs | `docs/<file>.md` | Team-wide coding standards and conventions |
| `memory` | Memory file | Project memory directory | Notes for future reference only |

### Repo File Decision Tree (Repo)

**Always read the target file before proposing a change.** Use this decision tree to pick the right file — wrong placement has happened before (learnings routed to `AGENTS.md` that belonged in style guide docs).

**Is it a convention/pattern a developer should follow when writing code?**
- Frontend component pattern, React hook usage, routing, lazy-loading, TypeScript → `repo-docs:docs/CODING_STYLE_FRONTEND.md`
- Tailwind classes, color tokens, breakpoints, twMerge, CVA → `repo-docs:docs/TAILWIND_CONVENTIONS.md`
- Backend C# pattern, domain modelling, EF Core, enum design, DI, error handling → `repo-docs:docs/CODING_STYLE_BACKEND.md`
- API endpoint conventions, response shape, versioning, auth attributes → `repo-docs:docs/API_CONVENTIONS.md`
- i18n, translation keys, TranslationService workflow, defaultValue pattern → `repo-docs:docs/INTERNATIONALIZATION.md`
- Route URL paths, page name → full URL mapping → `repo-docs:docs/APP_SITEMAP.md`
- Frontend component library patterns (CVA, Radix, design tokens) → `repo-docs:docs/FRONTEND_COMPONENTS.md`
- Backend testing patterns, unit/integration test conventions → `repo-docs:docs/TESTING_GUIDELINES_BACKEND.md`

**Is it a service-specific operational gotcha** (not a coding convention — something you need to *run* or *operate*)?
- Database names for psql, service ports, Docker quirks, seed data gaps for a specific service → `agents-md:services/<SVC>/AGENTS.md` (e.g. `services/ServiceB/AGENTS.md`)
- Cross-service operational gotchas (auth script, local dev login, worktree ServiceC swap) → `agents-md:services/AGENTS.md`
- Frontend agent commands, quick-ref for running/building the web app → `agents-md:apps/web/AGENTS.md`

> ⚠️ **`apps/web/AGENTS.md` and `services/AGENTS.md` are NOT for coding conventions.** They are for quick-reference commands and agent-specific operational gotchas. If you catch yourself writing "use X pattern instead of Y" in an AGENTS.md, it belongs in a style guide doc instead.

**Is it monorepo-wide infrastructure/structure info** (project layout, docker compose, quick-start)?
→ `project-claude` (`CLAUDE.md` at repo root or `services/CLAUDE.md`)

> ⚠️ **`CLAUDE.md` is NOT for coding conventions either.** It's a quick-start reference for the repo structure and how to run things. Conventions go in `docs/`.

**Does it affect Dream Team agent behavior** (prompts, phases, coordination)?
→ `dream-team`

**Does it affect a standalone agent** (architect, backend-dev, etc.) outside Dream Team?
→ `agent:<name>`

**Is it general knowledge** not actionable as a shared rule?
→ `memory`

### Classification Rules (summary)

| Learning type | Correct destination |
|--------------|---------------------|
| Agent coordination, timing, prompting, phases | `dream-team` |
| Frontend coding pattern or convention | `repo-docs:docs/CODING_STYLE_FRONTEND.md` |
| Tailwind/styling convention | `repo-docs:docs/TAILWIND_CONVENTIONS.md` |
| Backend coding pattern or convention | `repo-docs:docs/CODING_STYLE_BACKEND.md` |
| API design convention | `repo-docs:docs/API_CONVENTIONS.md` |
| i18n / translation workflow | `repo-docs:docs/INTERNATIONALIZATION.md` |
| Route URL reference | `repo-docs:docs/APP_SITEMAP.md` |
| Service-specific operational gotcha | `agents-md:services/<SVC>/AGENTS.md` |
| Cross-service operational gotcha | `agents-md:services/AGENTS.md` |
| Frontend agent commands/quick-ref | `agents-md:apps/web/AGENTS.md` |
| Monorepo structure/quick-start | `project-claude` |
| Standalone agent behavior (outside Dream Team) | `agent:<name>` |
| Skill workflow improvement | `skill:<name>` |
| General knowledge, no actionable rule | `memory` |

A single learning can route to **multiple destinations** (e.g., "check API endpoints" → both `agent:architect` and `skill:review-pr`).

### Apply Modes: Direct vs Ticket+PR

Learnings split into two tracks based on who they affect:

**Direct apply** (personal config in `~/.claude/`, only affects you):
- `dream-team`, `agent:<name>`, `skill:<name>`, `global-claude`, `memory`
- These are edited immediately and synced with `/sync-config`

**Ticket + PR** (shared repo files, affects the whole team):
- `project-claude`, `agents-md:<path>`, `repo-docs`
- These are NOT written directly. Instead:
  1. Group all repo-bound learnings into a single Jira ticket
  2. Create a branch + PR with the proposed changes
  3. The team reviews the PR like any other code change

### Routing Workflow

1. **Scan** all "Deferred" items from `dream-team-learnings.md` that aren't struck through (`~~`). Also check items with destination hints from recent retros.

2. **Classify** each using the Repo File Decision Tree above. If the retro already tagged a destination hint, use it as a **starting point only** — verify it's correct using the decision tree. Retro destination hints are often wrong (e.g., coding conventions tagged as `agents-md:apps/web/AGENTS.md` when they belong in `docs/CODING_STYLE_FRONTEND.md`).

3. **Read each destination file** before proposing changes — understand what's already there so you add to the right section and avoid duplicates. Pay attention to the file's purpose: if it's a style guide, add to a relevant existing section. If it's an AGENTS.md, only add operational/command content — never coding conventions.

4. **Present the routing table** to the user, with the apply mode column:

   ```
   ## Learning Router — Proposed Destinations

   ### Direct Apply (personal config)
   | # | Learning | Source Session | Destination | File | Proposed Change |
   |---|---------|---------------|-------------|------|-----------------|
   | 1 | Kenji shares contracts late | PROJ-1359 | dream-team | my-dream-team.md | Add timing instruction to Kenji prompt |
   | 2 | Check API endpoints exist | PROJ-1562 | agent:architect + skill:review-pr | architect.md, review-pr.md | Add checklist item |
   | 3 | Theme token colors unreliable | PROJ-1569 | memory | ticket-patterns.md | Note only — convention goes to repo-docs |

   ### Ticket + PR (shared repo — needs team review)
   | # | Learning | Source Session | Destination | File | Proposed Change |
   |---|---------|---------------|-------------|------|-----------------|
   | 4 | Use Dapper for heavy SQL | PROJ-1359 | repo-docs | docs/CODING_STYLE_BACKEND.md | Add to DB / query section |
   | 5 | ServiceB soft-delete quirk | PROJ-1359 | agents-md:services/ServiceB | services/ServiceB/AGENTS.md | Add Known Issues section |
   | 6 | Date helper convention | PROJ-1692 | repo-docs | docs/CODING_STYLE_FRONTEND.md | Add date parsing section |
   | 7 | Theme token colors unreliable | PROJ-1569 | repo-docs | docs/TAILWIND_CONVENTIONS.md | Add warning next to token listing |

   ### No Route (already addressed or no longer relevant)
   - [item] — [reason it's skipped]
   ```

5. **Ask the user** to approve routing using AskUserQuestion:
   - "Route all" — Apply direct items + create ticket/PR for repo items
   - "Let me pick" — User selects which rows to apply
   - "Save routing plan only" — Record the proposed routing in learnings file without applying
   - "Skip routing"

6. **Apply direct items** to personal config files. For each:
   - Read the file first
   - Find the appropriate section (or create one like `## Learned Conventions` or `## Known Issues`)
   - Add the learning concisely — match the existing style of the file
   - Don't restructure the file, just append to the right section
   - After all direct items are applied, offer to run `/sync-config`

7. **Create ticket + PR for repo items**. If there are any repo-bound learnings:

   a. **Create a Jira ticket** with `acli`:
      ```bash
      acli jira workitem create --project PLRS --type Uppgift \
        --summary "Apply retro learnings to repo docs and conventions" \
        --description "<description with the table of proposed changes>"
      ```
      Check allowed issue types first if the create fails: `acli jira workitem create --help` or try `Task`, `Uppgift`, or `Story` depending on your project's config. If `acli` is unavailable, tell the user the ticket details to create manually.

   b. **Create a branch and PR** using `/workspace-launch` or manually:
      ```bash
      cd <monorepo>
      git checkout -b retro-learnings-<date>
      ```

   c. **Apply the repo changes** to the branch:
      - Edit each destination file (CLAUDE.md, AGENTS.md, docs/*.md)
      - Commit with message referencing the Jira ticket

   d. **Create a draft PR**:
      ```bash
      gh pr create --draft --title "PROJ-XXXX: Apply retro learnings to repo conventions" \
        --body "$(cat <<'EOF'
      ## Summary
      Applies learnings from Dream Team retrospectives to shared repo files.

      ## Changes
      [table of changes from the routing table]

      ## Source Sessions
      [list of session IDs these learnings came from]
      EOF
      )"
      ```

   e. **Report** the Jira ticket ID and PR URL to the user.

8. **Mark applied/ticketed items** in `dream-team-learnings.md`:
   - Direct items: `- ~~[description]~~ → Applied to [destination] on [date]`
   - Repo items: `- ~~[description]~~ → Ticketed as [PROJ-XXXX] / PR #[number] on [date]`
   - This prevents re-proposing already-handled learnings in future reviews

## Actions

After presenting the health report AND the routing table, ask the user:

- "Apply health report changes + route learnings" — Do both: edit `my-dream-team.md` with health report fixes AND run the full routing (direct apply + ticket/PR)
- "Apply health report changes only" — Only the `my-dream-team.md` changes (legacy behavior)
- "Route learnings only" — Skip health report changes, just run the routing
- "Save report" — Append the report to `dream-team-learnings.md` under a `## Team Review: [date]` heading
- "Skip"

## Tips

- Run this periodically (e.g., every 5-10 sessions) to keep the team calibrated
- The report gets more useful with more data — early sessions may not show clear patterns
- Focus on **recurring** issues, not one-off problems
- The Learning Router is most valuable after 3+ sessions — that's when deferred learnings pile up
- Learnings routed to `project-claude` or `agents-md` help ALL Claude sessions, not just Dream Team — this is how lite-mode and raw Claude sessions benefit from Dream Team retros
- Repo-bound learnings go through PR review so the whole team can weigh in — this prevents one person's retro from silently changing shared conventions
