#!/bin/bash
# dtf-env.sh — Source this file in any script that needs Dream Team Flow config.
# Usage: source ~/.claude/scripts/dtf-env.sh
#
# Exports DTF_* environment variables from ~/.claude/dtf-config.json.
# Falls back to sensible defaults if config doesn't exist.

DTF_CONFIG="$HOME/.claude/dtf-config.json"

if [[ ! -f "$DTF_CONFIG" ]]; then
  # Fallback defaults (works without config for backward compatibility)
  export DTF_MONOREPO="$HOME/Documents/Repo"
  export DTF_WORKTREE_PARENT="$HOME/Documents"
  export DTF_WORKFLOW_REPO=""
  export DTF_GH_USER=""
  export DTF_TERMINAL="Alacritty"
  export DTF_USER_NAME=""
  return 0 2>/dev/null || exit 0
fi

# Require jq
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required for dtf-env.sh. Install with: brew install jq" >&2
  return 1 2>/dev/null || exit 1
fi

# Extract core values
export DTF_MONOREPO=$(jq -r '.paths.monorepo // "~/Documents/Repo"' "$DTF_CONFIG" | sed "s|~|$HOME|")
export DTF_WORKTREE_PARENT=$(jq -r '.paths.worktreeParent // "~/Documents"' "$DTF_CONFIG" | sed "s|~|$HOME|")
export DTF_WORKFLOW_REPO=$(jq -r '.paths.workflowRepo // ""' "$DTF_CONFIG" | sed "s|~|$HOME|")
export DTF_GH_USER=$(jq -r '.user.githubUsername // ""' "$DTF_CONFIG")
export DTF_TERMINAL=$(jq -r '.terminal // "Alacritty"' "$DTF_CONFIG")
export DTF_USER_NAME=$(jq -r '.user.name // ""' "$DTF_CONFIG")

# Export extra paths as DTF_EXTRA_<KEY> (uppercased, hyphens to underscores)
while IFS='=' read -r _dtf_key _dtf_value; do
  [[ -z "$_dtf_key" ]] && continue
  _dtf_var="DTF_EXTRA_$(echo "$_dtf_key" | tr '[:lower:]-' '[:upper:]_')"
  export "$_dtf_var"="$_dtf_value"
done < <(jq -r '.extraPaths // {} | to_entries[] | "\(.key)=\(.value)"' "$DTF_CONFIG" 2>/dev/null || true)
unset _dtf_key _dtf_value _dtf_var
