# Claude Code Integrations

Reference for all Claude Code integrations — what's active, what needs setup, and prerequisites.

## Team Setup — DTF CLI

**Status:** Active
**Location:** `~/.claude/scripts/dtf.sh`

Dream Team Flow is designed for team-wide deployment. The `dtf` CLI handles installation, updates, and shared learnings across a team.

### Architecture

```
Public repo (generic framework)
  │
  ├─ Company forks privately, adds company-config.json
  │   └─ service names, Jira domain, default paths, extra paths
  │
  └─ Team members install from fork (or public + company-config file)
      └─ dtf install <URL> --company-config company-config.json
          ├─ Interactive wizard (personal: name, paths, terminal)
          ├─ Symlinks commands/scripts/agents into ~/.claude/
          ├─ De-sanitizes generic names → real company names
          └─ Generates CLAUDE.md from template
```

### Commands

| Command | What it does |
|---------|-------------|
| `dtf install <URL> [--company-config <path>]` | Full setup: clone, wizard, symlinks, de-sanitize, generate CLAUDE.md |
| `dtf update` | Pull latest, verify symlinks, re-merge settings, regenerate CLAUDE.md |
| `dtf doctor` | Health check: config, symlinks, required tools (jq, tmux, gh) |
| `dtf contribute` | Export session retro learnings as a PR to the workflow repo |

### Company Config (`company-config.json`)

Shared by a team lead with new members. Defines company-specific values:

```json
{
  "projectName": "YourProject",
  "repoUrl": "git@github.com:your-org/your-repo.git",
  "ticketPrefix": "PROJ",
  "jiraDomain": "your-company.atlassian.net",
  "services": {
    "ServiceA": "RealNameA",
    "ServiceB": "RealNameB"
  },
  "defaultPaths": {
    "monorepo": "~/Documents/YourProject",
    "worktreeParent": "~/Documents"
  },
  "extraPaths": {
    "frontendApp": {
      "description": "Frontend app directory (relative to monorepo)",
      "default": "apps/web"
    }
  }
}
```

- **Services**: Any number — companies add/remove as needed
- **Default paths**: Suggested during install, users can override
- **Extra paths**: Project-specific paths the team uses, each with description and default. Users are asked to set each one during install, and can add their own custom paths on top.

### Personal Config (`~/.claude/dtf-config.json`)

Per-user, never committed. Created by `dtf install`:

```json
{
  "version": 1,
  "user": { "name": "...", "githubUsername": "..." },
  "paths": { "monorepo": "...", "worktreeParent": "...", "workflowRepo": "..." },
  "extraPaths": { "frontendApp": "apps/web" },
  "terminal": "Alacritty"
}
```

All command files read this config via a **Config Resolution** section — paths adapt per user automatically.

### Shared Learnings

After Dream Team sessions, retro learnings stay local per user. When ready to share:
1. Run `dtf contribute` — creates a PR with your learnings
2. Team reviews and curates into `learnings/aggregated-learnings.md`
3. Everyone pulls via `dtf update` — aggregated learnings available to all agents

### Onboarding a New Team Member

1. Team lead shares `company-config.json` (Slack, email, or in the company fork)
2. New member runs: `dtf install <REPO_URL> --company-config company-config.json`
3. Answers personal questions (name, monorepo path, terminal)
4. Done — all commands, scripts, agents, hooks are symlinked and ready

### Files

| File | Purpose |
|------|---------|
| `scripts/dtf.sh` | Main CLI |
| `scripts/dtf-env.sh` | Config loader (exports DTF_* vars for scripts) |
| `dtf-config.template.json` | Template for personal config |
| `company-config.example.json` | Example company config with all options documented |
| `CLAUDE.md.template` | Template with `{{MONOREPO_PATH}}`, `{{TERMINAL}}` placeholders |

---

## Active Integrations

### Hooks (Notifications + Guardrails)

**Status:** Active
**Location:** `~/.claude/settings.json`

| Hook | Event | What it does |
|------|-------|-------------|
| Tool usage logging | PostToolUse | Logs all tool calls to file for analytics |
| Desktop notification | Notification | macOS notification when Claude needs attention (idle, permission prompt, auth) |
| Migration guard | PostToolUse (Edit/Write) | Warns when editing files in `migrations/` directories |
| Lock file guard | PostToolUse (Edit/Write) | Warns when editing `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` |
| Auto-lint reminder | PostToolUse (Edit/Write) | Reminds to run CSharpier (.cs) or ESLint (.ts/.tsx) before committing |
| Teammate idle gate | TeammateIdle | Prevents dev agents from going idle without notes, journal, and clean formatting |
| Task completed gate | TaskCompleted | Prevents dev agents from marking tasks complete without notes, journal, "For Next Phase", code changes, and passing type checks |

To add more hooks, edit `~/.claude/settings.json` or run `/hooks` interactively.

### Custom Subagents

**Status:** Active
**Location:** `~/.claude/agents/`

| Agent | Model | Tools | Purpose |
|-------|-------|-------|---------|
| `architect` | Opus | Read-only + Bash | Architecture analysis, conventions summaries, implementation plans |
| `backend-dev` | Sonnet | Full | .NET backend implementation |
| `frontend-dev` | Sonnet | Full | React/TypeScript frontend implementation |
| `pr-reviewer` | Opus | Read-only + Bash | Code review with categorized feedback |
| `data-engineer` | Sonnet | Full | Data mapping, migrations, pipelines |

**Usage:** Claude automatically delegates to these when relevant, or invoke explicitly:
```
Use the pr-reviewer subagent to review the changes in this PR
Use the architect subagent to analyze what files need changing for this feature
```

**Relationship to Dream Team:** These are general-purpose standalone agents. The Dream Team (`/my-dream-team`) uses its own detailed prompts with team coordination, context management, and phase-specific instructions on top of the same core expertise.

### GitHub Actions — Claude Code in CI

**Status:** Workflow created, needs API key setup
**Location:** `~/Documents/Repo/.github/workflows/claude.yml`

**What it does:**
- Responds to `@claude` mentions in PR comments and issues
- Can auto-review PRs on open (disabled by default, uncomment to enable)
- Uses Sonnet with 15-turn limit and 30-minute timeout

**Prerequisites (must be done by a repo admin):**

1. **Install the Claude GitHub App:**
   ```
   https://github.com/apps/claude
   ```
   Required permissions: Contents (R/W), Issues (R/W), Pull Requests (R/W)

2. **Add API key as repository secret:**
   - Go to Repo repo → Settings → Secrets and variables → Actions
   - Create secret: `ANTHROPIC_API_KEY` with your Claude API key
   - Get key from: https://console.anthropic.com

3. **Test it:**
   - Comment `@claude explain this PR` on any pull request
   - Claude responds in the PR thread with analysis

**Cost considerations:**
- Each `@claude` invocation consumes GitHub Actions minutes + API tokens
- Sonnet is cost-effective; switch to Opus in `claude_args` for deeper analysis
- 30-minute timeout prevents runaway jobs

### Review PR (Fast + Full modes)

**Status:** Active
**Location:** `~/.claude/commands/review-pr.md`

Three ways to invoke:
- `/review-pr` — Auto-detects PR from current branch (fast mode)
- `/review-pr <PR>` — Fast: GitHub API only
- `/review-pr <PR> --full` — Full: local worktree at `.claude/worktrees/` + builds + deeper review

See the command file for full workflow details.

### Pre-Push Quality Gate

**Status:** Active
**Location:** `~/.claude/scripts/quality-gate.sh`

Deterministic pre-push script that runs formatting, linting, type checks, and builds without burning LLM tokens. Called by the team lead before `git push`:

```bash
bash ~/.claude/scripts/quality-gate.sh <worktree-path> [--backend] [--frontend] [--all]
```

- Auto-detects backend/frontend from changed files if no flags given
- Auto-fixes formatting (CSharpier for C#, Prettier + ESLint for TypeScript)
- Runs `dotnet build` (backend) and `tsc --noEmit` (frontend)
- Exits 0 if all checks pass, 1 if any fail
- Referenced in `~/.claude/docs/dev-workflow-checklist.md` Section 5

### CI & AI Review Polling

**Status:** Active
**Location:** `~/.claude/scripts/poll-ci-checks.sh`, `~/.claude/scripts/poll-ai-reviews.sh`

Used by the Dream Team in Phase 5.5 (after PR push) to wait for CI and AI bot reviews before proceeding:
- **poll-ci-checks.sh** — Polls GitHub Actions check runs until all pass, any fail, or timeout. Early exits on first failure. Logs timing to `~/.claude/logs/ci-check-times.csv`. **CI iteration cap: 2 rounds max** — after 2 failed fix attempts, escalate to user instead of retrying.
- **poll-ai-reviews.sh** — Polls for AI bot review comments (Gemini, Copilot, CodeRabbit, etc.) until found or timeout. Logs timing to `~/.claude/logs/ai-review-times.csv`.

Both scripts are standalone and can be used outside Dream Team:
```bash
bash ~/.claude/scripts/poll-ci-checks.sh RepoAB/Repo 1709 10 30
bash ~/.claude/scripts/poll-ai-reviews.sh RepoAB/Repo 1709 6 45
```

---

## Requires External Setup

### Slack Integration

**Status:** Not configured — requires Claude Code on the Web
**Docs:** https://code.claude.com/docs/en/slack

**What it would do:**
- `@Claude` in Slack channels routes coding tasks to Claude Code sessions
- Context from Slack threads informs the work
- Progress updates posted back to the thread
- "Create PR" button directly from Slack

**Prerequisites:**

| Requirement | Details |
|-------------|---------|
| Claude Plan | Pro, Max, Teams, or Enterprise with Claude Code access |
| Claude Code on the Web | Must be enabled at claude.ai/code |
| GitHub Account | Connected to Claude Code on the Web with Repo repo authenticated |
| Slack App | Claude app installed from Slack Marketplace by workspace admin |
| Slack Auth | Individual Slack account linked to Claude account |

**Setup steps:**
1. Workspace admin installs Claude app: https://slack.com/marketplace/A08SF47R6P4
2. Each user connects their Claude account via App Home → Connect
3. Configure Claude Code on the Web at claude.ai/code with GitHub repo access
4. Choose routing mode: "Code only" or "Code + Chat"
5. Invite Claude to channels: `/invite @Claude`

**Limitations:**
- GitHub only (no GitLab, Bitbucket)
- One PR at a time per session
- Rate limits apply per individual user plan
- Only works in channels, not DMs

### Code Intelligence Plugin

**Status:** Not installed — check marketplace availability
**Docs:** https://code.claude.com/docs/en/discover-plugins#code-intelligence

**What it would do:**
- Precise "go to definition" and "find references" navigation
- Automatic error detection after edits
- Better type hierarchy understanding

**Setup:**
```
# Inside Claude Code, run:
/plugin
# Browse marketplace for TypeScript/C# code intelligence plugins
```

**Benefit for Repo:** TypeScript + C# stack means two language servers worth of navigation. Especially useful for:
- Verifying imports resolve during PR reviews
- Following type hierarchies in EF Core models
- Finding all references to a changed interface

### Plugin Packaging (Future)

**Status:** Partially superseded by DTF CLI
**Docs:** https://code.claude.com/docs/en/plugins

The `dtf install` command now handles what plugin packaging would do — one-command installation with symlinks and auto-updates. A native Claude Code plugin could still be valuable for:
- Marketplace discoverability
- Automatic version management by Claude Code itself
- Tighter integration with `/plugin` command

**When to consider:** If Claude Code's plugin ecosystem matures and offers advantages over the current `dtf` approach (e.g., automatic updates without `dtf update`, conflict resolution with other plugins).

---

## Best Practices Applied

From https://code.claude.com/docs/en/best-practices:

| Practice | How we use it |
|----------|--------------|
| **Give Claude verification** | Dream Team Phase 2 baseline + Phase 5 drift check + `quality-gate.sh` |
| **Explore first, plan, then code** | Phase 1 (architect) → Phase 2 (implementation). Pre-hydrated context from `/create-stories` accelerates Phase 1. |
| **Provide specific context** | CLAUDE.md, AGENTS.md files, conventions docs |
| **Use CLI tools** | `gh`, `acli jira`, `docker compose` |
| **Context management** | Agent notes in `.dream-team/notes/`, `/compact` |
| **Writer/Reviewer pattern** | Maya reviews after Kenji/Ingrid implement |
| **Subagent investigation** | Architect subagent explores before devs code |
| **Headless mode** | `claude -p` used in sync-config, CI workflows |
| **Hooks for guardrails** | Tool usage logging, desktop notifications, migration guard, lock file guard, lint reminders, teammate idle gate, task completed gate |

---

## File Locations

| Integration | Files |
|-------------|-------|
| DTF CLI | `~/.claude/scripts/dtf.sh`, `~/.claude/scripts/dtf-env.sh` |
| Quality gate | `~/.claude/scripts/quality-gate.sh` |
| Teammate idle gate | `~/.claude/scripts/teammate-idle-gate.sh` |
| Task completed gate | `~/.claude/scripts/task-completed-gate.sh` |
| DTF Config (personal) | `~/.claude/dtf-config.json` |
| DTF Config (template) | `<workflow-repo>/dtf-config.template.json` |
| Company Config (example) | `<workflow-repo>/company-config.example.json` |
| CLAUDE.md template | `<workflow-repo>/CLAUDE.md.template` |
| Hooks | `~/.claude/settings.json` |
| Subagents | `~/.claude/agents/*.md` |
| GitHub Actions | `<monorepo>/.github/workflows/claude.yml` |
| Commands | `~/.claude/commands/*.md` |
| Scripts | `~/.claude/scripts/*.sh` |
| Skills | `~/.claude/skills/*/SKILL.md` |
| This doc | `~/.claude/docs/integrations.md` |
