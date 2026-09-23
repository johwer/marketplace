#!/usr/bin/env bash
# ticket-spec.sh — local implementation specs for Jira tickets.
#
# The spec lives at ~/Downloads/<TICKET_ID>/spec.md next to the ticket's
# screenshots and attachments. Jira keeps a short human-readable summary;
# the spec carries what an agent actually needs to implement.
#
# Usage:
#   ticket-spec.sh init <TICKET_ID> [--type story|subtask|spike|bug] [--parent <TICKET_ID>]
#   ticket-spec.sh path <TICKET_ID>
#   ticket-spec.sh resolve <TICKET_ID>            # validate + print inherited chain
#   ticket-spec.sh hydrate <TICKET_ID> <WORKTREE> # append spec + parents to jira-ticket.md
set -euo pipefail

DOWNLOADS="${TICKET_SPEC_ROOT:-$HOME/Downloads}"
MAX_DEPTH=4
VALID_TYPES="story subtask spike bug"

spec_path() { echo "$DOWNLOADS/$1/spec.md"; }

# Read one frontmatter key from a spec file. Empty string if absent.
fm() {
  awk -v key="$2" '
    NR==1 && $0 != "---" { exit }
    NR==1 { infm=1; next }
    infm && $0 == "---" { exit }
    infm {
      i = index($0, ":")
      if (i == 0) next
      k = substr($0, 1, i-1)
      v = substr($0, i+1)
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      gsub(/^"|"$/, "", v)
      if (k == key) { print v; exit }
    }
  ' "$1"
}

# Print a "## Heading" section (heading line included), or nothing.
section() {
  awk -v want="$2" '
    /^## / {
      h = substr($0, 4)
      gsub(/^[ \t]+|[ \t]+$/, "", h)
      inside = (tolower(h) == tolower(want))
      if (inside) { print; next }
    }
    inside { print }
  ' "$1"
}

body_after_frontmatter() {
  awk 'NR==1 && $0=="---" { infm=1; next } infm && $0=="---" { infm=0; next } !infm { print }' "$1"
}

die() { echo "ERROR: $*" >&2; exit 1; }

cmd_init() {
  local ticket="$1"; shift
  local type="" parent=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --type)   type="$2"; shift 2 ;;
      --parent) parent="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  local path; path="$(spec_path "$ticket")"
  [ -f "$path" ] && { echo "$path"; echo "EXISTS" >&2; exit 0; }
  [ -n "$type" ] || type="subtask"
  case " $VALID_TYPES " in *" $type "*) ;; *) die "type must be one of: $VALID_TYPES" ;; esac

  mkdir -p "$(dirname "$path")"
  {
    echo "---"
    echo "ticket: $ticket"
    echo "type: $type"
    [ -n "$parent" ] && echo "parent: $parent"
    echo "goal: <one line — what is true in the product when this is done>"
    echo "---"
    echo
    echo "## Goal"
    echo
    echo "<Why this exists. For a subtask: which part of the parent's goal it delivers.>"
    echo
    echo "## Requirements"
    echo
    echo "- <what must be true — behaviour, not implementation>"
    echo
    echo "## Contracts"
    echo
    echo "<Endpoints, payloads, types, feature flags, permissions this touches. Omit if none.>"
    echo
    echo "## Out of scope"
    echo
    echo "- <what this ticket must NOT change — binding on children>"
    echo
    echo "## Decisions"
    echo
    echo "<!-- Append as they are made. Never delete — strike through superseded ones. -->"
    echo
    echo "## Open questions"
    echo
    echo "- <unresolved — blocks implementation until answered>"
  } > "$path"
  echo "$path"
}

# Walk parent: links upward. Prints one ticket id per line, nearest parent first.
chain() {
  local ticket="$1" depth=0 seen=" "
  while :; do
    local p; p="$(spec_path "$ticket")"
    [ -f "$p" ] || break
    local parent; parent="$(fm "$p" parent)"
    [ -n "$parent" ] || break
    case "$seen" in *" $parent "*) die "parent cycle detected at $parent" ;; esac
    seen="$seen$parent "
    depth=$((depth+1))
    [ "$depth" -gt "$MAX_DEPTH" ] && die "parent chain deeper than $MAX_DEPTH (likely a mistake)"
    echo "$parent"
    ticket="$parent"
  done
}

cmd_resolve() {
  local ticket="$1"
  local path; path="$(spec_path "$ticket")"
  [ -f "$path" ] || { echo "NO_SPEC"; exit 0; }

  local type; type="$(fm "$path" type)"
  [ -n "$type" ] || die "$path: missing 'type' in frontmatter (one of: $VALID_TYPES)"
  case " $VALID_TYPES " in *" $type "*) ;; *) die "$path: type '$type' invalid (one of: $VALID_TYPES)" ;; esac

  local parent; parent="$(fm "$path" parent)"
  if [ "$type" = "subtask" ] && [ -z "$parent" ]; then
    die "$path: type is 'subtask' but no 'parent' is set — a subtask must name its story"
  fi

  echo "spec: $path"
  echo "type: $type"
  local missing=""
  while read -r p; do
    [ -n "$p" ] || continue
    if [ -f "$(spec_path "$p")" ]; then
      echo "parent: $p ($(spec_path "$p"))"
    else
      echo "parent: $p (NO SPEC ON DISK)"
      missing="$missing $p"
    fi
  done < <(chain "$ticket")
  [ -n "$missing" ] && echo "warning: parent spec missing for:$missing — inherited goal and out-of-scope are unavailable" >&2
  exit 0
}

cmd_hydrate() {
  local ticket="$1" worktree="$2"
  local target="$worktree/.dream-team/jira-ticket.md"
  [ -d "$worktree/.dream-team" ] || mkdir -p "$worktree/.dream-team"
  [ -f "$target" ] || die "$target does not exist — write the Jira output first, then hydrate"

  local path; path="$(spec_path "$ticket")"
  if [ ! -f "$path" ]; then
    echo "NO_SPEC"
    exit 0
  fi
  # Subshell: cmd_resolve exits on success, and must not take hydrate with it.
  ( cmd_resolve "$ticket" >/dev/null ) || exit 1   # fail loudly on a malformed spec first

  # Idempotent: drop any previously hydrated block before appending a fresh one.
  if grep -q '^<!-- ticket-spec:begin -->$' "$target"; then
    awk '/^<!-- ticket-spec:begin -->$/ { skip=1 } !skip { print } /^<!-- ticket-spec:end -->$/ { skip=0 }' \
      "$target" > "$target.tmp" && mv "$target.tmp" "$target"
  fi
  # Drop trailing blank lines so repeated hydration does not grow the file.
  awk 'NF { blank=0; for (i=0; i<held; i++) print ""; held=0; print; next } { held++ }' \
    "$target" > "$target.tmp" && mv "$target.tmp" "$target"

  local type; type="$(fm "$path" type)"
  {
    echo
    echo "<!-- ticket-spec:begin -->"
    echo "# Implementation spec — SOURCE OF TRUTH"
    echo
    echo "Hydrated from \`$path\` on $(date +%Y-%m-%d)."
    echo "Type: **$type**."
    echo
    echo "**Precedence:** where this spec and the Jira text above disagree, the spec wins —"
    echo "Jira is the human summary, this is what was actually decided. Where the spec and an"
    echo "inherited parent section disagree, raise it as a conflict; do not silently pick one."
    echo
    body_after_frontmatter "$path"
    echo

    local first=1
    while read -r p; do
      [ -n "$p" ] || continue
      local pp; pp="$(spec_path "$p")"
      if [ "$first" = 1 ]; then
        echo "---"
        echo
        echo "# Inherited from parent story"
        echo
        echo "These are binding. The parent's goal is what this work is for; the parent's"
        echo "out-of-scope and decisions constrain this ticket even though they are not repeated"
        echo "in it. If implementing this ticket requires breaking one of them, stop and ask."
        echo
        first=0
      fi
      echo "## $p"
      echo
      if [ -f "$pp" ]; then
        local g; g="$(fm "$pp" goal)"
        [ -n "$g" ] && { echo "**Goal:** $g"; echo; }
        # Demote to ### so parent sections nest under the parent ticket heading.
        { section "$pp" "Goal"; echo; section "$pp" "Out of scope"; echo; section "$pp" "Decisions"; } | sed "s|^## |### |"
        echo
      else
        echo "_No local spec at \`$pp\`. Run \`acli jira workitem view $p\` and read it before"
        echo "assuming scope — the parent's constraints are unknown._"
        echo
      fi
    done < <(chain "$ticket")

    echo "<!-- ticket-spec:end -->"
  } >> "$target"

  echo "HYDRATED $target"
}

case "${1:-}" in
  init)    shift; [ $# -ge 1 ] || die "usage: init <TICKET_ID> [--type T] [--parent P]"; cmd_init "$@" ;;
  path)    shift; [ $# -eq 1 ] || die "usage: path <TICKET_ID>"; spec_path "$1" ;;
  resolve) shift; [ $# -eq 1 ] || die "usage: resolve <TICKET_ID>"; cmd_resolve "$1" ;;
  hydrate) shift; [ $# -eq 2 ] || die "usage: hydrate <TICKET_ID> <WORKTREE>"; cmd_hydrate "$1" "$2" ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
