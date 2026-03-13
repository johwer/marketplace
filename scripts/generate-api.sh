#!/bin/bash
# generate-api.sh — Run RTK Query codegen with worktree-aware ports
#
# DTF standalone script — works from outside the Repo repo.
# In a worktree, reads port overrides from apps/web/.env.local and generates
# the API client using the correct Swagger URL. In main repo, uses defaults.
#
# Usage:
#   bash ~/.claude/scripts/generate-api.sh <service>
#   bash ~/.claude/scripts/generate-api.sh all
#   bash ~/.claude/scripts/generate-api.sh --worktree <path> <service>
#   bash ~/.claude/scripts/generate-api.sh <service> <TICKET_ID>
#
# Worktree detection (in order):
#   1. --worktree <path>         Explicit path
#   2. <TICKET_ID> as last arg   Resolves via dtf-config or ~/Documents/<ID>
#   3. CWD auto-detect           If CWD is inside a worktree or main repo
#
# Available services: service-c, service-a, service-e, service-b, service-d

set -euo pipefail

# --- Resolve paths from dtf-config.json or defaults ---
DTF_CONFIG="$HOME/.claude/dtf-config.json"
if [ -f "$DTF_CONFIG" ] && command -v jq &>/dev/null; then
    WORKTREE_PARENT=$(jq -r '.paths.worktreeParent // empty' "$DTF_CONFIG" 2>/dev/null)
    MEDHELP_ROOT=$(jq -r '.paths.monorepo // empty' "$DTF_CONFIG" 2>/dev/null)
fi
WORKTREE_PARENT="${WORKTREE_PARENT:-$HOME/Documents}"
MEDHELP_ROOT="${MEDHELP_ROOT:-$HOME/Documents/Repo}"

PROJECT_ROOT=""

# --- Parse --worktree flag ---
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --worktree)
            PROJECT_ROOT="$2"
            shift 2
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${ARGS[@]}"

# --- Auto-detect project root ---
if [ -z "$PROJECT_ROOT" ]; then
    local_cwd="$PWD"
    # Check if CWD is inside a worktree
    if [[ "$local_cwd" == "$WORKTREE_PARENT"/* && "$local_cwd" != "$MEDHELP_ROOT"* ]]; then
        relative="${local_cwd#$WORKTREE_PARENT/}"
        ticket_dir="${relative%%/*}"
        PROJECT_ROOT="$WORKTREE_PARENT/$ticket_dir"
    # Check if last arg looks like a ticket ID
    elif [[ $# -ge 2 && "${!#}" =~ ^[A-Z]+-[0-9]+$ ]]; then
        PROJECT_ROOT="$WORKTREE_PARENT/${!#}"
        set -- "${@:1:$(($#-1))}"
    # Check if CWD is inside main repo
    elif [[ "$local_cwd" == "$MEDHELP_ROOT"* ]]; then
        PROJECT_ROOT="$MEDHELP_ROOT"
    else
        echo "ERROR: Cannot detect project root. Use --worktree <path> or cd into a worktree." >&2
        exit 1
    fi
fi

WEB_DIR="$PROJECT_ROOT/apps/web"
API_DIR="$WEB_DIR/src/api"
ENV_FILE="$WEB_DIR/.env.local"

if [ ! -d "$WEB_DIR" ]; then
    echo "ERROR: Web app directory not found: $WEB_DIR" >&2
    exit 1
fi

# Default ports (same as main stack)
declare -A DEFAULT_PORTS=(
    [service-c]=5001
    [service-a]=5002
    [service-e]=5003
    [service-b]=5005
    [service-d]=5006
)

# Map service name to env var name in .env.local
declare -A ENV_VAR_NAMES=(
    [service-c]=VITE_ServiceC_API_PORT
    [service-a]=VITE_ABSENCE_API_PORT
    [service-e]=VITE_STATISTICS_API_PORT
    [service-b]=VITE_ServiceB_API_PORT
    [service-d]=VITE_MESSENGER_API_PORT
)

# Read port for a service (from .env.local or default)
get_port() {
    local service=$1
    local var_name="${ENV_VAR_NAMES[$service]}"
    local default="${DEFAULT_PORTS[$service]}"

    if [ -f "$ENV_FILE" ]; then
        local port
        port=$(grep "^${var_name}=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        if [ -n "$port" ]; then
            echo "$port"
            return
        fi
    fi
    echo "$default"
}

# Generate API client for a single service
generate_service() {
    local service=$1
    local port
    port=$(get_port "$service")
    local config_file="$API_DIR/openapi-config-${service}.ts"

    if [ ! -f "$config_file" ]; then
        echo "ERROR: Config file not found: $config_file" >&2
        return 1
    fi

    local default_port="${DEFAULT_PORTS[$service]}"

    if [ "$port" = "$default_port" ]; then
        echo "Generating $service API client (port $port)..."
        cd "$WEB_DIR" && npx @rtk-query/codegen-openapi "src/api/openapi-config-${service}.ts"
    else
        echo "Generating $service API client (worktree port $port)..."
        local temp_config="$API_DIR/.openapi-config-${service}-worktree.ts"

        trap "rm -f '$temp_config'" EXIT

        sed "/schemaFile:/ s|localhost:${default_port}|localhost:${port}|" "$config_file" > "$temp_config"

        cd "$WEB_DIR" && npx @rtk-query/codegen-openapi "src/api/.openapi-config-${service}-worktree.ts"

        rm -f "$temp_config"
        trap - EXIT
    fi

    echo "  Done: $service"
}

SERVICE="${1:?Usage: $0 <service|all>}"

if [ "$SERVICE" = "all" ]; then
    for svc in service-c service-a service-e service-b service-d; do
        generate_service "$svc"
    done
else
    if [ -z "${DEFAULT_PORTS[$SERVICE]+x}" ]; then
        echo "Unknown service: $SERVICE"
        echo "Available: service-c, service-a, service-e, service-b, service-d"
        exit 1
    fi
    generate_service "$SERVICE"
fi
