#!/bin/bash
# write-worktree-claude-md.sh — Write a CLAUDE.md to a worktree so spawned Claude sessions know about DTF
# Usage: bash ~/.claude/scripts/write-worktree-claude-md.sh <TICKET_ID>
set -eo pipefail

TICKET_ID="${1:?Usage: $0 <TICKET_ID>}"

# Resolve paths
DTF_CONFIG="$HOME/.claude/dtf-config.json"
if [ -f "$DTF_CONFIG" ] && command -v jq &>/dev/null; then
  WORKTREE_PARENT=$(jq -r '.paths.worktreeParent // empty' "$DTF_CONFIG" 2>/dev/null)
  MONOREPO=$(jq -r '.paths.monorepo // empty' "$DTF_CONFIG" 2>/dev/null)
fi
WORKTREE_PARENT="${WORKTREE_PARENT:-$HOME/Documents}"
MONOREPO="${MONOREPO:-$HOME/Documents/Repo}"
WORKTREE="$WORKTREE_PARENT/$TICKET_ID"

if [ ! -d "$WORKTREE" ]; then
  echo "ERROR: Worktree not found at $WORKTREE" >&2
  exit 1
fi

# Read port info from .env.local
VITE_PORT=""
if [ -f "$WORKTREE/apps/web/.env.local" ]; then
  VITE_PORT=$(grep '^VITE_DEV_PORT=' "$WORKTREE/apps/web/.env.local" 2>/dev/null | cut -d= -f2)
fi

# Read ServiceB port from root .env
ServiceB_PORT=""
if [ -f "$WORKTREE/.env" ]; then
  ServiceB_PORT=$(grep '^ServiceB_API_PORT=' "$WORKTREE/.env" 2>/dev/null | cut -d= -f2)
fi

# Copy the monorepo's CLAUDE.md as base and append DTF worktree section
if [ -f "$MONOREPO/CLAUDE.md" ]; then
  cp "$MONOREPO/CLAUDE.md" "$WORKTREE/CLAUDE.md"
else
  echo "# Repo Monorepo" > "$WORKTREE/CLAUDE.md"
fi

cat >> "$WORKTREE/CLAUDE.md" << EOF

## DTF Worktree — $TICKET_ID

**You are running inside a DTF (Dream Team Flow) worktree.** This is NOT the main repo.

### IMPORTANT: Behavioral Rules
1. **Questions are NOT implementation requests.** If the user asks "how does X work?" — answer the question. Do NOT start coding until explicitly told to implement.
2. **Follow the DTF workflow.** Read the context files below, follow the pre-hydrated plan. Do NOT skip steps or go rogue.
3. **Discussions about future work are discussions**, not instructions. Engage with the idea, don't implement it.

### Critical: Read These First
- \`.dream-team/jira-ticket.md\` — the Jira ticket you're implementing
- \`.dream-team/context.md\` — pre-hydrated analysis (scope, key files, conventions)
- \`.dream-team/notes/\` — any notes from previous sessions (if resuming)

### This Worktree's Ports
- Vite dev server: http://localhost:${VITE_PORT:-UNKNOWN}
- ServiceB API (if started): http://localhost:${ServiceB_PORT:-UNKNOWN}
- All other APIs proxy to the main stack (500x) by default

### Run the dev server (worktree)
- Use: \`cd apps/web && npx vite --config vite.config.worktree.mts --host\`
- Do **NOT** use \`npm start\` — it loads \`vite.config.mts\` (port 3000) and conflicts with other worktrees.

### Per-worktree local-state files — NEVER commit
\`apps/web/vite.config.worktree.mts\`, \`AGENTS.md\`, and \`CLAUDE.md\` are **per-worktree local state**, not code changes. They are generated/rewritten by DTF scripts — \`allocate-ports.sh\` generates the Vite config, \`worktree-service.sh up/down\` rewrites its proxy targets via \`sed\`, and worktree setup appends a DTF section to AGENTS.md/CLAUDE.md. Running Vite does **not** modify them; only the scripts do. \`allocate-ports.sh\` marks them \`git update-index --skip-worktree\` so git ignores the local edits — they will not appear in \`git status\` and cannot be staged. **Never** \`git update-index --no-skip-worktree\` them, and never \`git add\` them by path. Always stage your changes by **explicit path** (never \`git add -A\`/glob), and run \`prettier\`/\`eslint\` on your **named changed files only** (never \`--write .\`).

### Key DTF Scripts
\`\`\`bash
# Start a backend service (builds Docker, runs on worktree ports)
bash ~/.claude/scripts/worktree-service.sh up service-b-api

# Generate API types from a running worktree service
bash ~/.claude/scripts/generate-api.sh service-b

# Check worktree service status
bash ~/.claude/scripts/worktree-service.sh status

# Quality gate (run before push)
bash ~/.claude/scripts/quality-gate.sh $WORKTREE
\`\`\`

### Workflow Rules
1. **Follow the DTF workflow steps** — read \`.dream-team/context.md\` before coding
2. **Use worktree ports** — never hardcode port 3000 or 500x; use the ports from .env.local
3. **Visual verification** — use the \`playwright-cli\` skill for all browser testing (NOT Puppeteer MCP)
4. **Before committing** — run \`bash ~/.claude/scripts/quality-gate.sh $WORKTREE\`
5. **Don't modify files outside this worktree** — especially not the main repo

### Conventions
See \`docs/\` in the monorepo root for:
- \`CODING_STYLE_FRONTEND.md\` — React/TypeScript conventions
- \`CODING_STYLE_BACKEND.md\` — .NET/C# conventions
- \`TESTING.md\` — test patterns and requirements
EOF

echo "Wrote CLAUDE.md to $WORKTREE/CLAUDE.md"
