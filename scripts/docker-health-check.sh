#!/usr/bin/env bash
# docker-health-check.sh — Quick health snapshot of the Repo docker stack.
#
# Flags any repo-* container that is:
#   - not running (or exited within the last hour)
#   - reporting docker healthcheck status = unhealthy
#   - over CPU_THRESHOLD% CPU in a single snapshot
#   - has restarted >= RESTART_THRESHOLD times
#
# Appends every issue to ~/.claude/data/docker-health-log.jsonl so recurrence
# can be detected across runs (setup-time + ad-hoc mid-session).
#
# Human-readable root-cause evidence is collected separately in
# ~/.claude/data/docker-health-findings.md — when an issue is worth
# understanding (especially recurring ones), add a curated entry there.
#
# Exit codes:
#   0 — no issues
#   1 — issues found (or recurring issues from history)
#   2 — docker not installed / daemon unreachable
#
# Callable standalone any time:
#   bash ~/.claude/scripts/docker-health-check.sh
#
# Compatible with macOS bash 3.2 (no mapfile, no associative arrays).

set -uo pipefail

CPU_THRESHOLD=80
RESTART_THRESHOLD=5
RECURRENCE_DAYS=7
LOG_DIR="${HOME}/.claude/data"
LOG_FILE="${LOG_DIR}/docker-health-log.jsonl"
NAME_PREFIX="repo-"

# --- Pre-flight ---
if ! command -v docker &>/dev/null; then
  echo "⚠ docker CLI not installed."
  exit 2
fi
if ! docker info &>/dev/null; then
  echo "⚠ docker daemon not reachable. Is Docker Desktop running?"
  exit 2
fi

mkdir -p "$LOG_DIR"

# --- Snapshot ---
containers_file=$(mktemp)
docker ps -a --filter "name=${NAME_PREFIX}" --format '{{.Names}}' > "$containers_file"

container_count=$(wc -l < "$containers_file" | tr -d ' ')
if [ "$container_count" = "0" ]; then
  rm -f "$containers_file"
  echo "✓ No ${NAME_PREFIX}* containers present — nothing to check."
  exit 0
fi

# CPU snapshot once for the whole stack
stats_file=$(mktemp)
docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}' 2>/dev/null \
  | grep "^${NAME_PREFIX}" > "$stats_file" || true

# --- Diagnose ---
issues_file=$(mktemp)
now_epoch=$(date -u +%s)

while IFS= read -r c; do
  [ -z "$c" ] && continue
  status=$(docker inspect "$c" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  health=$(docker inspect "$c" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || echo "unknown")
  restarts=$(docker inspect "$c" --format '{{.RestartCount}}' 2>/dev/null || echo "0")
  cpu_raw=$(grep "^${c}|" "$stats_file" | head -1 | cut -d'|' -f2)
  cpu_int=0
  if [ -n "$cpu_raw" ]; then
    cpu_int=$(echo "$cpu_raw" | tr -d '%' | cut -d. -f1)
    case "$cpu_int" in ''|*[!0-9]*) cpu_int=0 ;; esac
  fi

  if [ "$status" = "exited" ]; then
    finished=$(docker inspect "$c" --format '{{.State.FinishedAt}}' 2>/dev/null || echo "")
    if [ -n "$finished" ] && [ "$finished" != "0001-01-01T00:00:00Z" ]; then
      finished_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "${finished%.*}" "+%s" 2>/dev/null || echo 0)
      if [ "$finished_epoch" -gt 0 ] && [ $((now_epoch - finished_epoch)) -lt 3600 ]; then
        printf '%s|status|exited\n' "$c" >> "$issues_file"
      fi
    fi
  elif [ "$status" != "running" ]; then
    printf '%s|status|%s\n' "$c" "$status" >> "$issues_file"
  fi

  [ "$health" = "unhealthy" ] && printf '%s|health|unhealthy\n' "$c" >> "$issues_file"
  [ "$cpu_int" -ge "$CPU_THRESHOLD" ] && printf '%s|cpu|%s\n' "$c" "$cpu_raw" >> "$issues_file"
  [ "$restarts" -ge "$RESTART_THRESHOLD" ] && printf '%s|restarts|%s\n' "$c" "$restarts" >> "$issues_file"
done < "$containers_file"

issue_count=$(wc -l < "$issues_file" | tr -d ' ')

# --- Recurrence check ---
recurring_file=$(mktemp)
if [ "$issue_count" -gt 0 ] && [ -f "$LOG_FILE" ] && command -v jq &>/dev/null; then
  cutoff_epoch=$(date -u -v-${RECURRENCE_DAYS}d +%s 2>/dev/null || date -u -d "${RECURRENCE_DAYS} days ago" +%s)
  while IFS='|' read -r name kind _val; do
    [ -z "$name" ] && continue
    count=$(jq -r --arg n "$name" --arg k "$kind" --argjson cutoff "$cutoff_epoch" \
      'select(.container == $n and .kind == $k and (.ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) >= $cutoff) | 1' \
      "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -ge 1 ]; then
      printf '%s|%s|%s\n' "$name" "$kind" "$count" >> "$recurring_file"
    fi
  done < "$issues_file"
fi

# --- Append findings to log ---
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
while IFS='|' read -r name kind val; do
  [ -z "$name" ] && continue
  printf '{"ts":"%s","container":"%s","kind":"%s","value":"%s"}\n' \
    "$ts" "$name" "$kind" "$val" >> "$LOG_FILE"
done < "$issues_file"

# --- Report ---
if [ "$issue_count" = "0" ]; then
  rm -f "$containers_file" "$stats_file" "$issues_file" "$recurring_file"
  echo "✓ All ${container_count} ${NAME_PREFIX}* containers healthy."
  exit 0
fi

echo "⚠ Docker health check found ${issue_count} issue(s):"
echo ""
while IFS='|' read -r name kind val; do
  [ -z "$name" ] && continue
  case "$kind" in
    status)   echo "  • ${name} — status: ${val}" ;;
    health)   echo "  • ${name} — healthcheck: ${val}" ;;
    cpu)      echo "  • ${name} — CPU at ${val} (threshold ${CPU_THRESHOLD}%)" ;;
    restarts) echo "  • ${name} — RestartCount: ${val} (threshold ${RESTART_THRESHOLD})" ;;
  esac
done < "$issues_file"

recurring_count=$(wc -l < "$recurring_file" | tr -d ' ')
if [ "$recurring_count" -gt 0 ]; then
  echo ""
  echo "Recurring (same symptom in last ${RECURRENCE_DAYS}d):"
  while IFS='|' read -r name kind count; do
    [ -z "$name" ] && continue
    echo "  • ${name} — ${kind} flagged ${count} prior time(s)"
  done < "$recurring_file"
fi

echo ""
echo "Log:      ${LOG_FILE}"
echo "Evidence: ${HOME}/.claude/data/docker-health-findings.md"
rm -f "$containers_file" "$stats_file" "$issues_file" "$recurring_file"
exit 1
