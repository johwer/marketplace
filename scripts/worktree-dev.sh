#!/usr/bin/env bash
# worktree-dev.sh — reliably (re)start the Vite app server + React Cosmos for a DTF worktree.
#
# Fixes the two recurring dev-server failure modes in worktrees:
#   1. Zombie processes still holding a dev port (esp. the Cosmos renderer) so a restart
#      can't rebind and keeps serving a stale/broken instance.
#   2. The app Vite and Cosmos Vite sharing node_modules/.vite — each one's dep
#      re-optimization invalidates the other's cached hashes → "504 Outdated Optimize Dep"
#      (white/blank app) and "Multiple script paths" (stale Cosmos renderer).
#      allocate-ports.sh now gives Cosmos its own cacheDir; this script does the clean
#      (re)start + renderer warm-up.
#
# Ports are read from the worktree's own config files (no hardcoding):
#   - Vite app port      <- apps/web/vite.config.worktree.mts  (first 3xxx `port:` literal)
#   - Cosmos UI port     <- apps/web/cosmos.worktree.config.json  (.port)
#   - Cosmos renderer    <- apps/web/cosmos.worktree.config.json  (.rendererUrl)
#
# Usage:
#   worktree-dev.sh [--worktree <dir>] [--hard] [--no-cosmos]
#     (no args)      restart from the current worktree (auto-detected)
#     --worktree DIR target a specific worktree root
#     --hard         also wipe node_modules/.vite + .vite-cosmos (forces clean optimize)
#     --no-cosmos    start only the Vite app server
set -euo pipefail

WT=""
HARD=0
START_COSMOS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree) WT="$2"; shift 2 ;;
    --hard) HARD=1; shift ;;
    --no-cosmos) START_COSMOS=0; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# --- locate the worktree root (walk up for apps/web/vite.config.worktree.mts) ---
if [[ -z "$WT" ]]; then
  d="$PWD"
  while [[ "$d" != "/" ]]; do
    [[ -f "$d/apps/web/vite.config.worktree.mts" ]] && { WT="$d"; break; }
    d="$(dirname "$d")"
  done
fi
[[ -z "$WT" || ! -f "$WT/apps/web/vite.config.worktree.mts" ]] && {
  echo "✗ Not in a DTF worktree (no apps/web/vite.config.worktree.mts found). Pass --worktree <dir>." >&2
  exit 1
}
WEB="$WT/apps/web"
cd "$WEB"

# --- read ports from the worktree config files ---
VITE_PORT="$(grep -oE 'port:\s*3[0-9]{3}' vite.config.worktree.mts | grep -oE '3[0-9]{3}' | head -1)"
COSMOS_PORT=""
RENDERER_PORT=""
if [[ -f cosmos.worktree.config.json ]] && command -v jq &>/dev/null; then
  COSMOS_PORT="$(jq -r '.port // empty' cosmos.worktree.config.json)"
  RENDERER_PORT="$(jq -r '.rendererUrl // empty' cosmos.worktree.config.json | grep -oE '[0-9]{4}$' || true)"
fi
[[ -z "$VITE_PORT" ]] && { echo "✗ Could not read the Vite port from vite.config.worktree.mts" >&2; exit 1; }
[[ "$START_COSMOS" == 1 && ( -z "$COSMOS_PORT" || -z "$RENDERER_PORT" ) ]] && {
  echo "⚠ Could not read Cosmos ports (jq missing or no cosmos.worktree.config.json) — starting Vite only." >&2
  START_COSMOS=0
}

TICKET="$(basename "$WT")"
LOG_DIR="${TMPDIR:-/tmp}/dtf-dev/$TICKET"
mkdir -p "$LOG_DIR"

echo "▸ Worktree: $WT"
echo "▸ Ports: Vite $VITE_PORT${START_COSMOS:+, Cosmos $COSMOS_PORT, renderer $RENDERER_PORT}"

# --- kill anything on those ports + stray react-cosmos for THIS worktree ---
PORTS=("$VITE_PORT"); [[ "$START_COSMOS" == 1 ]] && PORTS+=("$COSMOS_PORT" "$RENDERER_PORT")
echo "▸ Killing existing processes on: ${PORTS[*]} ..."
for port in "${PORTS[@]}"; do
  for pid in $(lsof -t -i:"$port" 2>/dev/null || true); do kill -9 "$pid" 2>/dev/null || true; done
done
for pid in $(pgrep -f "react-cosmos" 2>/dev/null || true); do
  cwd="$(lsof -p "$pid" 2>/dev/null | awk '$4=="cwd"{print $NF}' | head -1)"
  [[ "$cwd" == "$WEB"* ]] && kill -9 "$pid" 2>/dev/null || true
done
sleep 2

if [[ "$HARD" == 1 ]]; then
  echo "▸ Wiping Vite optimize caches (app + cosmos) ..."
  rm -rf node_modules/.vite node_modules/.vite-cosmos
fi

echo "▸ Starting Vite (:$VITE_PORT) ..."
nohup npx vite --config vite.config.worktree.mts --host > "$LOG_DIR/vite.log" 2>&1 &
disown

if [[ "$START_COSMOS" == 1 ]]; then
  echo "▸ Starting Cosmos (:$COSMOS_PORT, renderer :$RENDERER_PORT) ..."
  nohup npx cosmos --config cosmos.worktree.config.json > "$LOG_DIR/cosmos.log" 2>&1 &
  disown
fi

wait_up() { # port name
  for _ in $(seq 1 40); do
    [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$1/" 2>/dev/null)" == "200" ]] && { echo "  ✓ $2 ready (:$1)"; return 0; }
    sleep 2
  done
  echo "  ✗ $2 did NOT come up on :$1 — check $LOG_DIR/$3"; return 1
}

wait_up "$VITE_PORT" "Vite app" "vite.log" || true
if [[ "$START_COSMOS" == 1 ]]; then
  wait_up "$COSMOS_PORT" "Cosmos UI" "cosmos.log" || true
  echo "▸ Warming up the Cosmos renderer (settles the dep optimize once) ..."
  curl -s -o /dev/null "http://localhost:$RENDERER_PORT/" 2>/dev/null || true
  sleep 8
  if curl -s "http://localhost:$RENDERER_PORT/" 2>/dev/null | grep -q "Multiple script paths"; then
    echo "  ⚠ renderer still warming — reload the page once in a few seconds."
  else
    echo "  ✓ renderer healthy"
  fi
fi

echo ""
echo "Ready:"
echo "  App:    http://localhost:$VITE_PORT/"
[[ "$START_COSMOS" == 1 ]] && echo "  Cosmos: http://localhost:$COSMOS_PORT/"
echo "  Logs:   $LOG_DIR/"
echo ""
echo "If the app goes white or Cosmos shows 'Multiple script paths' again, re-run this script."
