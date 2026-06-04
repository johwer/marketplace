# Parallel Worktrees — How It Works

## Overview

DTF supports running multiple worktrees simultaneously, each with isolated ports, Docker containers, and generated API types. This lets you work on two (or more) tickets at the same time without conflicts.

## Port Isolation

Each worktree gets a unique **slot** (derived from ticket number mod 99):

| Component | Slot 07 (NOVA-2580) | Slot 08 (NOVA-2581) | Main stack |
|-----------|---------------------|---------------------|------------|
| Vite dev server | 3107 | 3108 | 3000 |
| Cosmos UI | 3907 | 3908 | 3999 |
| Cosmos renderer | 3807 | 3808 | 3998 |
| ServiceC API | 10701 | 10801 | 5001 |
| ServiceA API | 10702 | 10802 | 5002 |
| ServiceE API | 10703 | 10803 | 5003 |
| ServiceB API | 10705 | 10805 | 5005 |
| ServiceD API | 10706 | 10806 | 5006 |

**Port formula:**
- Vite: `3100 + slot`
- Cosmos UI: `3900 + slot` / Cosmos renderer: `3800 + slot`
- API services: `10000 + (slot * 100) + service_offset`

Collision detection: if two tickets hash to the same slot, the second one increments until free.

## How dev-server ports ACTUALLY resolve (read this when a port looks wrong)

A worktree allocates ports, but each dev server resolves its port differently. Knowing
which mechanism is *honored* is the difference between "it just works" and "why is it on
3000 again." The short version:

| Server | What allocate-ports.sh writes | What the tool ACTUALLY reads at runtime | Command that uses the right port |
|--------|-------------------------------|-----------------------------------------|----------------------------------|
| **Vite dev** | `VITE_DEV_PORT` in `.env.local` **(dead — nothing reads it)** + `vite.config.worktree.mts` (port baked in by `sed`) | the `port:` literal in whichever config file is loaded | `npx vite --config vite.config.worktree.mts --host` |
| **Cosmos** | `cosmos.worktree.config.json` (`port` + `rendererUrl` patched) | `port` + `rendererUrl` straight from the config file it's given | `npx cosmos --config cosmos.worktree.config.json` |

### Vite — the gotcha
`apps/web/vite.config.mts` calls `loadEnv()` (so `.env.local` *is* loaded into
`process.env`) **but then hardcodes `server.port: 3000`** and hardcodes the proxy targets
to `5001–5006`. It never reads `VITE_DEV_PORT`. Consequences:

- **`npm start` in a worktree silently runs on 3000** — it uses the default config. To get
  the worktree port you MUST run `npx vite --config vite.config.worktree.mts --host`.
- `VITE_DEV_PORT` in `.env.local` is vestigial. It looks like it sets the port; it does not.
- The only thing that moves the Vite port is the `sed`-generated `vite.config.worktree.mts`.
- API proxies are switched by `worktree-service.sh` editing `vite.config.worktree.mts`
  directly (`switch_vite_proxy`), **not** by env vars. The `VITE_*_API_PORT` vars in
  `.env.local` are read only by `generate-api.sh` (to pick the codegen source port).

> Cleaner long-term fix (NOT done — it's a committed Repo repo file, so it needs a
> ticket / DTF, not an ad-hoc edit): make `vite.config.mts` read
> `Number(process.env.VITE_DEV_PORT) || 3000` and read proxy targets from
> `VITE_*_API_PORT`. Then `npm start` would honor the worktree port and
> `vite.config.worktree.mts` could be retired — one honored mechanism, like Cosmos.

### Cosmos — why it's more robust
react-cosmos reads `port` and `rendererUrl` *directly from the config file at runtime*
(`viteDevServerPlugin.js` binds the renderer to `new URL(rendererUrl).port`). There is no
env-var layer to drift out of sync. We pass `--config cosmos.worktree.config.json` and it
binds exactly those ports. The renderer port has **no CLI flag** — it can only come from
`rendererUrl` — which is why we generate a patched config file instead of passing a flag.

### Outside a worktree (main repo / non-DTF teammate)
`allocate-ports.sh` generates `vite.config.worktree.mts` and `cosmos.worktree.config.json`
**only inside worktrees**. The main repo never has them, so you just run the stock commands
(`npm start` → 3000, `npm run cosmos` → 3999/3998) against the committed configs. The
override files are additive, opt-in, and marked `skip-worktree`, so they never get committed
and never affect anyone not using DTF. The fallback is always "use the hardcoded defaults."

## File Structure Per Worktree

```
~/Documents/<TICKET_ID>/
  .env                          # COMPOSE_PROJECT_NAME, API ports
  .dream-team/                  # Context, notes, journals
    context.md                  # Pre-hydrated analysis
    jira-ticket.md              # Full Jira ticket text
  apps/web/
    .env.local                  # VITE_DEV_PORT, COSMOS_*_PORT, VITE_*_API_PORT
    vite.config.worktree.mts    # Vite config with unique port
    cosmos.worktree.config.json # React Cosmos config with unique UI + renderer ports
```

## How Services Run in Parallel

Each worktree's Docker containers use a unique `COMPOSE_PROJECT_NAME` (e.g., `repo-nova-2580`), so:
- Containers don't collide (different names)
- Ports don't collide (different slots)
- Volumes are namespaced per project
- All connect to the shared `repo_repo-network` for infrastructure (postgres, redis, rabbitmq)

```bash
# Worktree A: starts service-b-api on port 10705
cd ~/Documents/NOVA-2580
bash ~/.claude/scripts/worktree-service.sh up service-b-api

# Worktree B: starts service-b-api on port 10805 (different container!)
cd ~/Documents/NOVA-2581
bash ~/.claude/scripts/worktree-service.sh up service-b-api
```

## API Codegen Per Worktree

`generate-api.sh` reads the worktree's `.env.local` to find the correct port:

```bash
# In worktree A: generates types from localhost:10705
bash ~/.claude/scripts/generate-api.sh service-b

# In worktree B: generates types from localhost:10805
bash ~/.claude/scripts/generate-api.sh service-b
```

Each worktree gets its own generated TypeScript types matching its own backend changes.

## Proxy Strategy

By default, API proxies point to the **main stack** (500x ports). Only services you explicitly `worktree-service.sh up` get redirected to worktree ports. This means:
- You only rebuild what you changed
- Everything else uses the shared running services
- Zero overhead for services you don't touch

## Lifecycle Commands

### Create
```bash
/create-stories TICKET-A TICKET-B     # Full lifecycle: worktrees + Dream Team
/workspace-launch TICKET-A             # Single worktree + Dream Team
```

### Resume (after terminal close or next day)
```bash
# From the orchestrator:
resume NOVA-2580

# Or directly:
bash ~/.claude/scripts/resume-workspace.sh NOVA-2580
```

The resume script:
1. Verifies the worktree exists
2. Checks/regenerates `.env` and port allocations if missing
3. Detects stale Docker containers on worktree ports
4. Kills any orphan tmux session
5. Starts a fresh tmux session with Claude in `--resume` mode
6. Claude reads `.dream-team/` notes and journals to pick up where it left off

### Pause (end of day, keep everything)
```bash
bash ~/.claude/scripts/pause-workspace.sh NOVA-2580
```
Kills tmux + dev servers, preserves worktree, code, notes, git branches.

### Cleanup (after PR merge)
```bash
/workspace-cleanup NOVA-2580
# Or from orchestrator: "clean up NOVA-2580"
```

## Resuming After a Closed/Crashed Terminal

If your terminal dies (crash, restart, accidental close), nothing is lost:
- The **worktree** is on disk (`~/Documents/<TICKET_ID>/`)
- The **ports** are in `.env` and `.env.local`
- The **notes/journals** are in `.dream-team/`
- The **git branch** has all commits

Just resume:
```bash
bash ~/.claude/scripts/open-terminal.sh "Alacritty" "bash ~/.claude/scripts/resume-workspace.sh 'NOVA-2580'"
```
Or tell the orchestrator: `resume NOVA-2580`

The resume script re-validates ports, checks for conflicts, and launches a new tmux + Claude session that reads the existing `.dream-team/` context.
