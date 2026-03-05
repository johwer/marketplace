#!/bin/bash
# Chrome Browser Queue — cross-workspace coordination for Chrome Claude extension
# Only one workspace can use Chrome at a time. Agents self-organize via this queue.
#
# Usage:
#   chrome-queue.sh join <TICKET_ID> <AGENT_NAME>   — Add yourself to the queue
#   chrome-queue.sh my-turn <TICKET_ID>              — Check if you're first (exit 0=yes, 1=no)
#   chrome-queue.sh done <TICKET_ID>                 — Remove yourself from the queue
#   chrome-queue.sh heartbeat <TICKET_ID>            — Refresh your timestamp (keep your slot)
#   chrome-queue.sh status                           — Show current queue
#
# Stale entries (no heartbeat for 3+ min) are auto-skipped by my-turn.
# Teammates can run heartbeat on behalf of a busy agent.

set -euo pipefail

QUEUE_FILE="$HOME/.claude/chrome/queue.txt"
LOCK_FILE="$HOME/.claude/chrome/queue.lock"
STALE_SECONDS=180  # 3 minutes

# Ensure queue file exists
mkdir -p "$(dirname "$QUEUE_FILE")"
touch "$QUEUE_FILE"

# Simple file lock to prevent concurrent writes (mkdir-based, works on macOS)
acquire_file_lock() {
  local retries=0
  while ! mkdir "$LOCK_FILE" 2>/dev/null; do
    retries=$((retries + 1))
    if [ "$retries" -ge 50 ]; then
      # Force remove stale lock after 5 seconds
      rm -rf "$LOCK_FILE"
      mkdir "$LOCK_FILE" 2>/dev/null || { echo "ERROR: Could not acquire file lock"; exit 1; }
      break
    fi
    sleep 0.1
  done
}

release_file_lock() {
  rm -rf "$LOCK_FILE" 2>/dev/null || true
}

now_epoch() {
  date +%s
}

is_stale() {
  local timestamp="$1"
  local now
  now=$(now_epoch)
  local age=$(( now - timestamp ))
  [ "$age" -ge "$STALE_SECONDS" ]
}

# Remove stale entries from the top of the queue
clean_stale() {
  local cleaned=false
  local _t _a _ts
  while IFS=: read -r _t _a _ts || [ -n "$_t" ]; do
    [ -z "$_t" ] && continue
    if is_stale "$_ts"; then
      echo "STALE: Removing $_t:$_a (no heartbeat for 3+ min)"
      cleaned=true
    else
      break  # First non-stale entry found, stop cleaning
    fi
  done < "$QUEUE_FILE"

  if $cleaned; then
    # Rewrite file without stale entries from the top
    local tmp
    tmp=$(mktemp)
    local skipping=true
    while IFS=: read -r _t _a _ts || [ -n "$_t" ]; do
      [ -z "$_t" ] && continue
      if $skipping && is_stale "$_ts"; then
        continue
      else
        skipping=false
        echo "$_t:$_a:$_ts" >> "$tmp"
      fi
    done < "$QUEUE_FILE"
    mv "$tmp" "$QUEUE_FILE"
  fi
}

cmd_join() {
  local ticket="$1"
  local agent="$2"
  local now
  now=$(now_epoch)

  acquire_file_lock

  # Check if already in queue
  if grep -q "^${ticket}:${agent}:" "$QUEUE_FILE" 2>/dev/null; then
    # Already queued — just update timestamp
    local tmp
    tmp=$(mktemp)
    while IFS=: read -r t a ts || [ -n "$t" ]; do
      [ -z "$t" ] && continue
      if [ "$t" = "$ticket" ] && [ "$a" = "$agent" ]; then
        echo "$t:$a:$now" >> "$tmp"
      else
        echo "$t:$a:$ts" >> "$tmp"
      fi
    done < "$QUEUE_FILE"
    mv "$tmp" "$QUEUE_FILE"
    echo "UPDATED: $ticket:$agent already in queue, timestamp refreshed"
  else
    echo "$ticket:$agent:$now" >> "$QUEUE_FILE"
    echo "JOINED: $ticket:$agent added to queue"
  fi

  # Show position
  local pos=0
  while IFS=: read -r t a ts || [ -n "$t" ]; do
    [ -z "$t" ] && continue
    pos=$((pos + 1))
    if [ "$t" = "$ticket" ] && [ "$a" = "$agent" ]; then
      if [ "$pos" -eq 1 ]; then
        echo "STATUS: You're first — Chrome is yours. Remember to heartbeat!"
      else
        echo "STATUS: Position $pos in queue. Wait for my-turn to return 0."
      fi
      break
    fi
  done < "$QUEUE_FILE"

  release_file_lock
}

cmd_my_turn() {
  local ticket="$1"

  acquire_file_lock
  clean_stale

  # Check if first in queue
  local first_ticket first_agent first_ts
  IFS=: read -r first_ticket first_agent first_ts < "$QUEUE_FILE" 2>/dev/null || true

  release_file_lock

  if [ -z "$first_ticket" ]; then
    echo "EMPTY: Queue is empty. Join first."
    exit 1
  fi

  if [ "$first_ticket" = "$ticket" ]; then
    echo "YES: It's your turn ($ticket:$first_agent)"
    exit 0
  else
    echo "NO: $first_ticket:$first_agent has Chrome. You're waiting."
    exit 1
  fi
}

cmd_done() {
  local ticket="$1"

  # Kill Vite on port 3000 before releasing the queue — ensures next workspace can bind
  local vite_pid
  vite_pid=$(lsof -t -i:3000 2>/dev/null || true)
  if [ -n "$vite_pid" ]; then
    kill "$vite_pid" 2>/dev/null || true
    echo "PORT: Killed process on port 3000 (pid $vite_pid)"
  fi

  acquire_file_lock

  local tmp
  tmp=$(mktemp)
  local removed=false
  while IFS=: read -r t a ts || [ -n "$t" ]; do
    [ -z "$t" ] && continue
    if [ "$t" = "$ticket" ] && ! $removed; then
      echo "DONE: Removed $t:$a from queue"
      removed=true
    else
      echo "$t:$a:$ts" >> "$tmp"
    fi
  done < "$QUEUE_FILE"
  mv "$tmp" "$QUEUE_FILE"

  if ! $removed; then
    echo "NOT_FOUND: $ticket was not in the queue"
  fi

  # Show who's next
  local next_ticket next_agent next_ts
  IFS=: read -r next_ticket next_agent next_ts < "$QUEUE_FILE" 2>/dev/null || true
  if [ -n "$next_ticket" ]; then
    echo "NEXT: $next_ticket:$next_agent is now first in line"
  else
    echo "QUEUE: Empty — Chrome is free"
  fi

  release_file_lock
}

cmd_heartbeat() {
  local ticket="$1"
  local now
  now=$(now_epoch)

  acquire_file_lock

  local tmp
  tmp=$(mktemp)
  local found=false
  while IFS=: read -r t a ts || [ -n "$t" ]; do
    [ -z "$t" ] && continue
    if [ "$t" = "$ticket" ]; then
      echo "$t:$a:$now" >> "$tmp"
      found=true
    else
      echo "$t:$a:$ts" >> "$tmp"
    fi
  done < "$QUEUE_FILE"
  mv "$tmp" "$QUEUE_FILE"

  release_file_lock

  if $found; then
    echo "HEARTBEAT: $ticket timestamp refreshed"
  else
    echo "NOT_FOUND: $ticket is not in the queue"
    exit 1
  fi
}

cmd_status() {
  if [ ! -s "$QUEUE_FILE" ]; then
    echo "QUEUE: Empty — Chrome is free"
    exit 0
  fi

  echo "=== Chrome Browser Queue ==="
  local pos=0
  local now
  now=$(now_epoch)
  while IFS=: read -r ticket agent timestamp || [ -n "$ticket" ]; do
    [ -z "$ticket" ] && continue
    pos=$((pos + 1))
    local age=$(( now - timestamp ))
    local stale_marker=""
    if [ "$age" -ge "$STALE_SECONDS" ]; then
      stale_marker=" [STALE - will be skipped]"
    fi
    if [ "$pos" -eq 1 ]; then
      echo "  1. $ticket:$agent (holding, ${age}s ago)$stale_marker"
    else
      echo "  $pos. $ticket:$agent (waiting, queued ${age}s ago)$stale_marker"
    fi
  done < "$QUEUE_FILE"
}

# --- Main ---
CMD="${1:-}"
case "$CMD" in
  join)
    [ -z "${2:-}" ] || [ -z "${3:-}" ] && { echo "Usage: chrome-queue.sh join <TICKET_ID> <AGENT_NAME>"; exit 1; }
    cmd_join "$2" "$3"
    ;;
  my-turn)
    [ -z "${2:-}" ] && { echo "Usage: chrome-queue.sh my-turn <TICKET_ID>"; exit 1; }
    cmd_my_turn "$2"
    ;;
  done)
    [ -z "${2:-}" ] && { echo "Usage: chrome-queue.sh done <TICKET_ID>"; exit 1; }
    cmd_done "$2"
    ;;
  heartbeat)
    [ -z "${2:-}" ] && { echo "Usage: chrome-queue.sh heartbeat <TICKET_ID>"; exit 1; }
    cmd_heartbeat "$2"
    ;;
  status)
    cmd_status
    ;;
  *)
    echo "Chrome Browser Queue — cross-workspace coordination"
    echo ""
    echo "Usage:"
    echo "  chrome-queue.sh join <TICKET_ID> <AGENT_NAME>   — Join the queue"
    echo "  chrome-queue.sh my-turn <TICKET_ID>              — Check if it's your turn"
    echo "  chrome-queue.sh done <TICKET_ID>                 — Leave the queue"
    echo "  chrome-queue.sh heartbeat <TICKET_ID>            — Keep your slot alive"
    echo "  chrome-queue.sh status                           — Show the queue"
    exit 1
    ;;
esac
