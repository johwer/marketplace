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

# --- Early help ---
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "help" ] || [ $# -eq 0 ]; then
    head -19 "$0" | tail -17
    exit 0
fi

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
if [ ${#ARGS[@]} -gt 0 ]; then
    set -- "${ARGS[@]}"
else
    set --
fi

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

# Available services
SERVICES="service-c service-a service-e service-b service-d"

# Map service name → default port (main stack 500x)
default_port() {
    case "$1" in
        service-c)        echo 5001 ;;
        service-a)    echo 5002 ;;
        service-e) echo 5003 ;;
        service-b)        echo 5005 ;;
        service-d)  echo 5006 ;;
    esac
}

# Map service name → VITE env var name in .env.local
env_var_name() {
    case "$1" in
        service-c)        echo "VITE_ServiceC_API_PORT" ;;
        service-a)    echo "VITE_ABSENCE_API_PORT" ;;
        service-e) echo "VITE_STATISTICS_API_PORT" ;;
        service-b)        echo "VITE_ServiceB_API_PORT" ;;
        service-d)  echo "VITE_MESSENGER_API_PORT" ;;
    esac
}

# Read port for a service (from .env.local or default)
get_port() {
    local service=$1
    local var_name
    var_name=$(env_var_name "$service")
    local fallback
    fallback=$(default_port "$service")

    if [ -f "$ENV_FILE" ]; then
        local port
        port=$(grep "^${var_name}=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2)
        if [ -n "$port" ]; then
            echo "$port"
            return
        fi
    fi
    echo "$fallback"
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

    local def_port
    def_port=$(default_port "$service")

    if [ "$port" = "$def_port" ]; then
        echo "Generating $service API client (port $port)..."
        cd "$WEB_DIR" && npx @rtk-query/codegen-openapi "src/api/openapi-config-${service}.ts"
    else
        echo "Generating $service API client (worktree port $port)..."
        local temp_config="$API_DIR/.openapi-config-${service}-worktree.ts"

        trap "rm -f '$temp_config'" EXIT

        sed "/schemaFile:/ s|localhost:${def_port}|localhost:${port}|" "$config_file" > "$temp_config"

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
    if ! echo "$SERVICES" | grep -qw "$SERVICE"; then
        echo "Unknown service: $SERVICE"
        echo "Available: $SERVICES"
        exit 1
    fi
    generate_service "$SERVICE"
fi
