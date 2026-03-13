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
        echo ""
        echo "Service started. Check health:"
        echo "  bash ~/.claude/scripts/worktree-service.sh status"
        echo "  bash ~/.claude/scripts/worktree-service.sh logs $SERVICE"
        ;;
    down)
        echo "Stopping all worktree services ($WORKTREE_DIR)..."
        # Reset ServiceC host to main stack when stopping
        sed -i '' 's/^ServiceC_SERVICE_HOST=.*/ServiceC_SERVICE_HOST=service-c-api/' "$WORKTREE_DIR/.env" 2>/dev/null || true
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
