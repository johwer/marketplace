#!/bin/bash
# worktree-service.sh — Build and run a single API service from a worktree
#
# DTF standalone script — works from outside the Repo repo.
# Connects to the main stack's infrastructure (postgres, redis, rabbitmq, etc.)
# while running your worktree's code on a separate port.
#
# Usage:
#   bash ~/.claude/scripts/worktree-service.sh up <service>     Build & start a service
#   bash ~/.claude/scripts/worktree-service.sh down              Stop all worktree services
#   bash ~/.claude/scripts/worktree-service.sh logs <service>    Tail logs for a service
#   bash ~/.claude/scripts/worktree-service.sh ps               List running worktree services
#   bash ~/.claude/scripts/worktree-service.sh status           Show port mappings and health
#
# Worktree detection (in order):
#   1. --worktree <path>         Explicit path
#   2. <TICKET_ID> as last arg   Resolves via dtf-config or ~/Documents/<ID>
#   3. CWD auto-detect           If CWD is inside a worktree
#
# Available services (API only — workers/sync not yet supported):
#   service-b-api, service-a-api, service-e-api, service-d-api, service-c-api
#
# Examples:
#   bash ~/.claude/scripts/worktree-service.sh up service-b-api
#   bash ~/.claude/scripts/worktree-service.sh --worktree ~/Documents/PROJ-1234 up service-b-api
#   bash ~/.claude/scripts/worktree-service.sh down PROJ-1234

set -euo pipefail

COMPOSE_FILE="$HOME/.claude/templates/docker-compose.worktree.yml"
WORKTREE_DIR=""

# --- Resolve paths from dtf-config.json or defaults ---
DTF_CONFIG="$HOME/.claude/dtf-config.json"
if [ -f "$DTF_CONFIG" ] && command -v jq &>/dev/null; then
    WORKTREE_PARENT=$(jq -r '.paths.worktreeParent // empty' "$DTF_CONFIG" 2>/dev/null)
    MEDHELP_ROOT=$(jq -r '.paths.monorepo // empty' "$DTF_CONFIG" 2>/dev/null)
fi
WORKTREE_PARENT="${WORKTREE_PARENT:-$HOME/Documents}"
MEDHELP_ROOT="${MEDHELP_ROOT:-$HOME/Documents/Repo}"

# --- Early help ---
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "help" ] || [ $# -eq 0 ]; then
    head -26 "$0" | tail -24
    exit 0
fi

# --- Parse --worktree flag ---
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --worktree)
            WORKTREE_DIR="$2"
            shift 2
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done
if [ ${#ARGS[@]} -gt 0 ]; then
    set -- "${ARGS[@]}"
else
    set --
fi

# --- Auto-detect worktree ---
detect_worktree() {
    # Already set via --worktree
    if [ -n "$WORKTREE_DIR" ]; then
        return
    fi

    # Check if CWD is inside a worktree (not the main repo)
    local cwd="$PWD"
    if [[ "$cwd" == "$WORKTREE_PARENT"/* && "$cwd" != "$MEDHELP_ROOT"* ]]; then
        # Extract the first path component after WORKTREE_PARENT
        local relative="${cwd#$WORKTREE_PARENT/}"
        local ticket_dir="${relative%%/*}"
        WORKTREE_DIR="$WORKTREE_PARENT/$ticket_dir"
        return
    fi

    # Check if the last argument looks like a ticket ID (not a service name or command)
    local last_arg="${!#}"
    if [[ "$last_arg" =~ ^[A-Z]+-[0-9]+$ ]]; then
        WORKTREE_DIR="$WORKTREE_PARENT/$last_arg"
        # Remove the ticket ID from the args
        set -- "${@:1:$(($#-1))}"
        return
    fi

    echo "ERROR: Cannot detect worktree. Use one of:" >&2
    echo "  bash ~/.claude/scripts/worktree-service.sh --worktree <path> <command>" >&2
    echo "  bash ~/.claude/scripts/worktree-service.sh <command> <TICKET_ID>" >&2
    echo "  cd into a worktree and run from there" >&2
    exit 1
}

detect_worktree

if [ ! -d "$WORKTREE_DIR" ]; then
    echo "ERROR: Worktree directory does not exist: $WORKTREE_DIR" >&2
    exit 1
fi

if [ ! -f "$WORKTREE_DIR/.env" ]; then
    echo "ERROR: No .env file in $WORKTREE_DIR" >&2
    echo "Run: bash ~/.claude/scripts/allocate-ports.sh <TICKET_ID>" >&2
    exit 1
fi

# Verify main stack network exists
check_main_network() {
    local network
    network=$(grep '^MAIN_NETWORK=' "$WORKTREE_DIR/.env" 2>/dev/null | cut -d= -f2)
    network="${network:-repo_repo-network}"
    if ! docker network inspect "$network" &>/dev/null; then
        echo "ERROR: Main stack network '$network' not found."
        echo "Start the main stack first:"
        echo "  cd $MEDHELP_ROOT && docker compose up -d"
        exit 1
    fi
}

# Available services (user-facing names)
SERVICES="service-b-api service-a-api service-e-api service-d-api service-c-api"

# Map service name → main stack port (500x default)
main_stack_port() {
    case "$1" in
        service-c-api)        echo 5001 ;;
        service-a-api)    echo 5002 ;;
        service-e-api) echo 5003 ;;
        service-b-api)        echo 5005 ;;
        service-d-api)  echo 5006 ;;
    esac
}

# Map service name → worktree port (from .env)
worktree_port() {
    local env_key
    case "$1" in
        service-c-api)        env_key="ServiceC_API_PORT" ;;
        service-a-api)    env_key="ABSENCE_API_PORT" ;;
        service-e-api) env_key="STATISTICS_API_PORT" ;;
        service-b-api)        env_key="ServiceB_API_PORT" ;;
        service-d-api)  env_key="MESSENGER_API_PORT" ;;
    esac
    grep "^${env_key}=" "$WORKTREE_DIR/.env" 2>/dev/null | cut -d= -f2
}

# Map service name → VITE env var name in .env.local
vite_env_var() {
    case "$1" in
        service-c-api)        echo "VITE_ServiceC_API_PORT" ;;
        service-a-api)    echo "VITE_ABSENCE_API_PORT" ;;
        service-e-api) echo "VITE_STATISTICS_API_PORT" ;;
        service-b-api)        echo "VITE_ServiceB_API_PORT" ;;
        service-d-api)  echo "VITE_MESSENGER_API_PORT" ;;
    esac
}

# Switch a service's proxy in vite.config.worktree.mts to the given port
switch_vite_proxy() {
    local service="$1" new_port="$2"
    local old_port
    old_port=$(main_stack_port "$service")
    local vite_config="$WORKTREE_DIR/apps/web/vite.config.worktree.mts"
    [ -f "$vite_config" ] || return 0
    # Also handle the case where it was already switched to a worktree port
    local wt_port
    wt_port=$(worktree_port "$service")
    sed -i '' \
        -e "s#http://localhost:${old_port}\"#http://localhost:${new_port}\"#g" \
        -e "s#http://localhost:${wt_port}\"#http://localhost:${new_port}\"#g" \
        "$vite_config"
    echo "Updated vite proxy: $service → localhost:$new_port"
}

# Update VITE_*_API_PORT in .env.local so generate-api.sh picks up the right port
switch_env_local_port() {
    local service="$1" new_port="$2"
    local env_local="$WORKTREE_DIR/apps/web/.env.local"
    [ -f "$env_local" ] || return 0
    local var_name
    var_name=$(vite_env_var "$service")
    [ -n "$var_name" ] || return 0
    if grep -q "^${var_name}=" "$env_local" 2>/dev/null; then
        sed -i '' "s|^${var_name}=.*|${var_name}=${new_port}|" "$env_local"
    fi
}

# Map user-facing service name to compose service name.
# Worktree services are suffixed with "-wt" to avoid Docker DNS collisions
# with the main stack on the shared network.
to_compose_name() {
    echo "${1}-wt"
}

compose() {
    WORKTREE_BUILD_CONTEXT="$WORKTREE_DIR" docker compose \
        -f "$COMPOSE_FILE" \
        --project-directory "$WORKTREE_DIR" \
        --env-file "$WORKTREE_DIR/.env" \
        "$@"
}

case "${1:-help}" in
    up)
        SERVICE="${2:?Usage: $0 up <service>}"
        if ! echo "$SERVICES" | grep -qw "$SERVICE"; then
            echo "Unknown service: $SERVICE"
            echo "Available: $SERVICES"
            if [[ "$SERVICE" == *worker* || "$SERVICE" == *sync* || "$SERVICE" == *Worker* || "$SERVICE" == *Sync* ]]; then
                echo ""
                echo "Note: Workers and sync services are not yet supported in worktree mode."
                echo "They run from the main stack. To add support, edit:"
                echo "  ~/.claude/templates/docker-compose.worktree.yml"
                echo "  ~/.claude/scripts/worktree-service.sh (SERVICES list)"
            fi
            exit 1
        fi
        check_main_network
        COMPOSE_NAME=$(to_compose_name "$SERVICE")

        # When ServiceC is started from the worktree, other worktree services should
        # route authorization calls to it (not to the main stack's ServiceC).
        if [ "$SERVICE" = "service-c-api" ]; then
            if ! grep -q '^ServiceC_SERVICE_HOST=' "$WORKTREE_DIR/.env" 2>/dev/null; then
                echo "ServiceC_SERVICE_HOST=service-c-api-wt" >> "$WORKTREE_DIR/.env"
            else
                sed -i '' 's/^ServiceC_SERVICE_HOST=.*/ServiceC_SERVICE_HOST=service-c-api-wt/' "$WORKTREE_DIR/.env"
            fi
        fi

        echo "Building and starting $SERVICE from worktree ($WORKTREE_DIR)..."
        compose up --build -d "$COMPOSE_NAME"

        # Post-up smoke check. A container reports "Up" even when the .NET app crashed on
        # boot (e.g. missing S3 env → AddRepoS3() throws → host crash-loops at 100% CPU,
        # see NOVA-3183). Poll briefly and fail loudly with logs instead of reporting success
        # on a dead app.
        echo "Waiting for $SERVICE to start listening..."
        UP_OK=""
        STATE=""
        for _ in $(seq 1 15); do
            if compose logs "$COMPOSE_NAME" 2>/dev/null | grep -q "Now listening on"; then
                UP_OK="yes"; break
            fi
            STATE=$(compose ps --format '{{.State}}' "$COMPOSE_NAME" 2>/dev/null | head -1)
            case "$STATE" in
                exited|restarting|dead)
                    break ;;
            esac
            sleep 1
        done
        if [ -z "$UP_OK" ]; then
            echo ""
            echo "❌ $SERVICE did not start listening (container state: ${STATE:-unknown})."
            echo "   A crash-looping .NET app still shows 'Up' — last 30 log lines:"
            echo "   ----------------------------------------------------------------"
            compose logs --tail 30 "$COMPOSE_NAME" 2>&1 || true
            echo "   ----------------------------------------------------------------"
            echo "   Fix the boot error above, then re-run: bash ~/.claude/scripts/worktree-service.sh up $SERVICE"
            exit 1
        fi
        echo "✅ $SERVICE is listening."

        # Switch vite proxy and .env.local port for this service to the worktree port
        WT_PORT=$(worktree_port "$SERVICE")
        if [ -n "$WT_PORT" ]; then
            switch_vite_proxy "$SERVICE" "$WT_PORT"
            switch_env_local_port "$SERVICE" "$WT_PORT"
            echo ""
            echo "⚡ Vite proxy updated: $SERVICE → localhost:$WT_PORT"
            echo "⚡ .env.local updated: $(vite_env_var "$SERVICE")=$WT_PORT"
            echo "  Restart Vite to pick up the change:"
            echo "  cd apps/web && npx vite --config vite.config.worktree.mts --host"
            echo "  Generate API types: bash ~/.claude/scripts/generate-api.sh ${SERVICE%-api}"
        fi

        echo ""
        echo "Service started. Check health:"
        echo "  bash ~/.claude/scripts/worktree-service.sh status"
        echo "  bash ~/.claude/scripts/worktree-service.sh logs $SERVICE"
        ;;
    down)
        echo "Stopping all worktree services ($WORKTREE_DIR)..."
        # Reset ServiceC host to main stack when stopping
        sed -i '' 's/^ServiceC_SERVICE_HOST=.*/ServiceC_SERVICE_HOST=service-c-api/' "$WORKTREE_DIR/.env" 2>/dev/null || true

        # Revert all vite proxies and .env.local ports back to main stack (500x)
        for svc in $SERVICES; do
            MAIN_PORT=$(main_stack_port "$svc")
            switch_vite_proxy "$svc" "$MAIN_PORT" 2>/dev/null
            switch_env_local_port "$svc" "$MAIN_PORT" 2>/dev/null
        done
        echo "Vite proxies and .env.local reverted to main stack (500x)"

        compose down
        ;;
    logs)
        SERVICE="${2:?Usage: $0 logs <service>}"
        if ! echo "$SERVICES" | grep -qw "$SERVICE"; then
            echo "Unknown service: $SERVICE"
            echo "Available: $SERVICES"
            exit 1
        fi
        COMPOSE_NAME=$(to_compose_name "$SERVICE")
        compose logs -f "$COMPOSE_NAME"
        ;;
    ps)
        compose ps
        ;;
    status)
        echo "Worktree services ($WORKTREE_DIR):"
        compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || compose ps
        ;;
    help|--help|-h)
        head -26 "$0" | tail -24
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'bash ~/.claude/scripts/worktree-service.sh help' for usage."
        exit 1
        ;;
esac
