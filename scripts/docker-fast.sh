#!/usr/bin/env bash
# docker-fast.sh — Start/restart the Repo docker stack fast & safely, WITHOUT
# the full-stack parallel rebuild that OOMs Docker Desktop (exit 137) and triggers
# the R1 EF-migration zombie (containers stuck at 100% CPU).
#
# Deterministic, zero-LLM twin of the /docker-fast slash command. Run it directly
# on a daily basis:  docker-fast.sh rebuild
#
# THE CORE RULE: never `docker compose up -d --build` with no service args — that
# rebuilds ~19 .NET services in parallel (6–12 GB RAM → SIGKILL) and races
# concurrent EF migrations. This script always names services and caps parallelism.
#
# Modes (first positional arg):
#   up | (empty)        ensure infra, start all BACKEND detached, NO build (reuse images)
#   rebuild | pull      warm `up -d --build` of infra+backend (bake + cap): only changed
#                       services recompile. THE everyday command after `git pull`.
#                       Add --no-cache for a deliberate cold rebuild.
#   recover | restart   `down --remove-orphans` then `up -d` (no build). Fixes a broken
#                       half-up state. Volumes/data preserved (never -v).
#   infra               only postgres redis rabbitmq localstack localstack-init (+tools)
#   <domain>...         one+ of: service-c service-a service-b service-d service-e → that domain's
#                       api+workers plus infra (no build unless --build)
#   <service>...        exact compose service name(s) → infra + just those
#   reset <domain|svc>  drop+recreate ONE service's DB, bring it up, EF re-migrates from
#                       source. The escape hatch for migration DRIFT (renumbered migration
#                       vs stale local DB → 42P07). Destructive to that ONE DB; prompts
#                       unless --yes. NOT for routine use.
#   down                stop the stack cleanly (keeps volumes). `down --hard` = --remove-orphans
#   bench               timed cold build of the 19 .NET services (--warm = incremental)
#
# Flags:
#   --no-cache     force cold rebuild (rebuild mode)
#   --no-bake      opt out of buildx bake (fall back to classic per-service builder)
#   --build        rebuild the NAMED service(s)/domain only (ignored if nothing named)
#   --web          also include web-app + nginx (prod frontend on :3000)
#   --tools        also include pgadmin dozzle aspire-dashboard
#   --parallel N   COMPOSE_PARALLEL_LIMIT (default 4)
#   --warm         (bench only) skip --no-cache → measure incremental rebuild
#   --worktree     operate in the current directory's compose project (don't cd to main)
#   --yes | -y     skip the destructive-action confirmation (reset)
#   --dry-run      print the docker commands instead of running them
#   -h | --help    this help
#
# Env: MEDHELP_MONOREPO overrides the repo path (default ~/Documents/Repo).
# Compatible with macOS bash 3.2 (no associative arrays, no mapfile).

set -uo pipefail

REPO="${MEDHELP_MONOREPO:-$HOME/Documents/Repo}"
PG_CONTAINER="repo-postgres"
PG_USER="postgres"

# ---- service groups (categories) -------------------------------------------
INFRA=(postgres redis rabbitmq localstack localstack-init)
TOOLS=(pgadmin dozzle aspire-dashboard)
ServiceC=(service-c-api service-c-sync-api service-c-sync-worker service-c-worker-data-erasure service-c-worker-quarantine)
ABSENCE=(service-a-api service-a-sync-api service-a-worker-data-erasure service-a-worker-deviant service-a-worker-deviant-engine service-a-worker-quarantine)
ServiceB=(service-b-api service-b-worker service-b-worker-data-erasure service-b-worker-quarantine)
MESSENGER=(service-d-api service-d-worker-quarantine service-d-worker-sms-delivery)
STATISTICS=(service-e-api)
WEB=(web-app nginx)
BACKEND=("${ServiceC[@]}" "${ABSENCE[@]}" "${ServiceB[@]}" "${MESSENGER[@]}" "${STATISTICS[@]}")

# ---- defaults / flag state --------------------------------------------------
PARALLEL=4
BAKE=true
NO_CACHE=""
BUILD_FLAG=""
INCLUDE_WEB=0
INCLUDE_TOOLS=0
WARM=0
WORKTREE=0
ASSUME_YES=0
DRY_RUN=0

die() { echo "docker-fast: $*" >&2; exit 1; }

# domain name -> its service array, echoed space-separated. empty if not a domain.
domain_services() {
  case "$1" in
    service-c)        echo "${ServiceC[@]}" ;;
    service-a)    echo "${ABSENCE[@]}" ;;
    service-b)        echo "${ServiceB[@]}" ;;
    service-d)  echo "${MESSENGER[@]}" ;;
    service-e) echo "${STATISTICS[@]}" ;;
    *)          echo "" ;;
  esac
}

is_domain() { [ -n "$(domain_services "$1")" ]; }

# map a domain OR an exact service name to its domain key (for reset → DB name)
domain_of() {
  local x="$1"
  if is_domain "$x"; then echo "$x"; return; fi
  case "$x" in
    service-c-*|service-c)               echo "service-c" ;;
    service-a-*|service-a)       echo "service-a" ;;
    service-b-*|service-b)               echo "service-b" ;;
    service-d-*|service-d)   echo "service-d" ;;
    service-e-*|service-e) echo "service-e" ;;
    *)                       echo "" ;;
  esac
}

# run (or, under --dry-run, print) a command
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

usage() { sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; }

# ---- parse args -------------------------------------------------------------
MODE=""
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-cache)  NO_CACHE="--no-cache" ;;
    --no-bake)   BAKE=false ;;
    --build)     BUILD_FLAG="--build" ;;
    --web)       INCLUDE_WEB=1 ;;
    --tools)     INCLUDE_TOOLS=1 ;;
    --warm)      WARM=1 ;;
    --worktree)  WORKTREE=1 ;;
    --yes|-y)    ASSUME_YES=1 ;;
    --dry-run)   DRY_RUN=1 ;;
    --hard)      POSITIONAL+=("--hard") ;;
    --parallel)  shift; [ $# -gt 0 ] || die "--parallel needs N"; PARALLEL="$1" ;;
    -h|--help)   usage; exit 0 ;;
    -*)          die "unknown flag: $1 (see --help)" ;;
    *)           if [ -z "$MODE" ]; then MODE="$1"; else POSITIONAL+=("$1"); fi ;;
  esac
  shift
done
[ -z "$MODE" ] && MODE="up"

# optional add-ons for the whole-stack modes
ADDON=()
[ "$INCLUDE_TOOLS" = 1 ] && ADDON+=("${TOOLS[@]}")
[ "$INCLUDE_WEB" = 1 ] && ADDON+=("${WEB[@]}")

# ---- move to the right compose project --------------------------------------
if [ "$WORKTREE" = 1 ]; then
  echo "docker-fast: operating on the CURRENT directory's compose project ($(pwd))"
else
  [ -d "$REPO" ] || die "monorepo not found at $REPO (set MEDHELP_MONOREPO)"
  cd "$REPO" || die "cannot cd to $REPO"
fi

export COMPOSE_PARALLEL_LIMIT="$PARALLEL"

verify() {
  [ "$DRY_RUN" = 1 ] && return 0
  echo
  echo "--- verify (waiting 15s for health) ---"
  sleep 15
  docker compose ps --format 'table {{.Name}}\t{{.Status}}' 2>/dev/null
  echo "--- fail signals (empty = good; localstack-init exit 0 is normal) ---"
  docker compose ps -a --format '{{.Name}}\t{{.Status}}' 2>/dev/null \
    | grep -iE 'exit|unhealthy|restarting' | grep -v 'localstack-init' || echo "  (none)"
  echo "--- top CPU (flag anything near 100% = R1 zombie) ---"
  docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}' 2>/dev/null \
    | sort -t$'\t' -k2 -rn | head -5
}

# ---- modes ------------------------------------------------------------------
case "$MODE" in

  up)
    echo "docker-fast: up (no build) — infra + backend${ADDON:+ + addons}, cap=$PARALLEL"
    run docker compose up -d "${INFRA[@]}" "${BACKEND[@]}" ${ADDON+"${ADDON[@]}"}
    verify
    ;;

  recover|restart)
    echo "docker-fast: recover — down --remove-orphans (keeps volumes) then up -d, cap=$PARALLEL"
    run docker compose down --remove-orphans
    run docker compose up -d "${INFRA[@]}" "${BACKEND[@]}" ${ADDON+"${ADDON[@]}"}
    verify
    ;;

  rebuild|pull)
    export COMPOSE_BAKE="$BAKE"
    echo "docker-fast: rebuild — warm up -d --build (bake=$BAKE${NO_CACHE:+, $NO_CACHE}), cap=$PARALLEL"
    echo "            only changed services recompile; the rest hit cache."
    run docker compose up -d --build $NO_CACHE "${INFRA[@]}" "${BACKEND[@]}" ${ADDON+"${ADDON[@]}"}
    verify
    ;;

  infra)
    echo "docker-fast: infra only${INCLUDE_TOOLS:+ + tools}"
    if [ "$INCLUDE_TOOLS" = 1 ]; then
      run docker compose up -d "${INFRA[@]}" "${TOOLS[@]}"
    else
      run docker compose up -d "${INFRA[@]}"
    fi
    verify
    ;;

  down)
    HARD=0
    for p in ${POSITIONAL+"${POSITIONAL[@]}"}; do [ "$p" = "--hard" ] && HARD=1; done
    if [ "$HARD" = 1 ]; then
      echo "docker-fast: down --remove-orphans (keeps volumes)"
      run docker compose down --remove-orphans
    else
      echo "docker-fast: down (keeps volumes)"
      run docker compose down
    fi
    ;;

  bench)
    export COMPOSE_BAKE=true
    NC="--no-cache"; [ "$WARM" = 1 ] && NC=""
    echo "docker-fast: bench (bake, $([ -z "$NC" ] && echo warm/incremental || echo cold), cap=$PARALLEL) — baseline ~33m"
    if [ "$DRY_RUN" = 1 ]; then
      run docker compose build $NC "${BACKEND[@]}"
    else
      SECONDS=0
      docker compose build $NC "${BACKEND[@]}"
      echo "BENCH bake$([ -z "$NC" ] && echo '+warm' || echo '+cold'): ${SECONDS}s = $((SECONDS/60))m $((SECONDS%60))s   (baseline ~33m)"
    fi
    ;;

  reset)
    svc="${POSITIONAL+${POSITIONAL[0]:-}}"
    [ -n "$svc" ] || die "reset needs a domain or service, e.g. 'docker-fast.sh reset service-d'"
    dom="$(domain_of "$svc")"
    [ -n "$dom" ] || die "'$svc' is not a known domain/service (service-c service-a service-b service-d service-e)"
    DB="repo_${dom}"
    read -r -a SVCS <<< "$(domain_services "$dom")"

    echo "docker-fast: reset — domain '$dom', database '$DB'"
    echo "            (drift escape hatch: drops+recreates ONE DB so EF re-migrates from source)"

    # ensure postgres is up so we can talk to it
    run docker compose up -d "${INFRA[@]}" >/dev/null 2>&1

    if [ "$DRY_RUN" != 1 ]; then
      # guard: confirm the DB actually exists before we offer to drop it
      exists="$(docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d postgres -tAc \
        "select 1 from pg_database where datname='$DB';" 2>/dev/null)"
      if [ "$exists" != "1" ]; then
        echo "docker-fast: database '$DB' not found. Available repo_* databases:" >&2
        docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d postgres -tAc \
          "select datname from pg_database where datname like 'repo\\_%' order by 1;" 2>/dev/null | sed 's/^/  - /' >&2
        die "nothing to reset"
      fi
    fi

    if [ "$ASSUME_YES" != 1 ] && [ "$DRY_RUN" != 1 ]; then
      printf "  This DROPS and recreates '%s' (loses that service's local data). Continue? [y/N] " "$DB"
      read -r ans
      case "$ans" in y|Y|yes|YES) ;; *) die "aborted" ;; esac
    fi

    echo "  stopping $dom containers..."
    run docker compose stop "${SVCS[@]}"
    echo "  dropping + recreating $DB..."
    run docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d postgres -v ON_ERROR_STOP=1 \
      -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB' AND pid<>pg_backend_pid();" \
      -c "DROP DATABASE IF EXISTS \"$DB\";" \
      -c "CREATE DATABASE \"$DB\";"
    echo "  starting $dom (no build → EF migrates from source)..."
    run docker compose up -d "${SVCS[@]}"
    verify
    ;;

  *)
    # domain(s) and/or exact service name(s)
    read -r -a FIRST <<< "$(domain_services "$MODE")"
    TARGETS=()
    if [ ${#FIRST[@]} -gt 0 ]; then TARGETS+=("${FIRST[@]}"); else TARGETS+=("$MODE"); fi
    for p in ${POSITIONAL+"${POSITIONAL[@]}"}; do
      read -r -a MORE <<< "$(domain_services "$p")"
      if [ ${#MORE[@]} -gt 0 ]; then TARGETS+=("${MORE[@]}"); else TARGETS+=("$p"); fi
    done

    export COMPOSE_BAKE="$BAKE"
    echo "docker-fast: targeted — ${TARGETS[*]}${BUILD_FLAG:+ (build)}, cap=$PARALLEL"
    run docker compose up -d "${INFRA[@]}"           # ensure deps first
    if [ -n "$BUILD_FLAG" ]; then
      run docker compose up -d --build $NO_CACHE "${TARGETS[@]}"
    else
      run docker compose up -d "${TARGETS[@]}"
    fi
    verify
    ;;
esac
