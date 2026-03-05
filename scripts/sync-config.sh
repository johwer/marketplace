#!/bin/bash
# Sync Claude configuration files to two repos:
#   1. ~/Privat/shared-claude-files (private — exact copy, no sanitization)
#   2. ~/Privat/dream-team-flow (public — fully sanitized, no company references)

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PRIVATE_REPO="$HOME/Privat/shared-claude-files"
PUBLIC_REPO="$HOME/Privat/dream-team-flow"
GH_USER="johwer"

# Files and directories to track
declare -a TRACKED_FILES=(
  "CLAUDE.md"
  "settings.json"
  "commands/commands.md"
  "commands/my-dream-team.md"
  "commands/create-stories.md"
  "commands/workspace-launch.md"
  "commands/workspace-cleanup.md"
  "commands/acli-jira-cheatsheet.md"
  "commands/ticket-scout.md"
  "commands/sync-config.md"
  "commands/team-stats.md"
  "commands/retro-proposals.md"
  "commands/pr-insights.md"
  "commands/scrape-pr-history.md"
  "commands/review-pr.md"
  "commands/reviewers.md"
  "scripts/launch-workspace.sh"
  "scripts/resume-workspace.sh"
  "scripts/pause-workspace.sh"
  "scripts/sync-config.sh"
  "scripts/poll-ai-reviews.sh"
  "scripts/chrome-queue.sh"
  "scripts/tool-usage-log.sh"
  "scripts/poll-ci-checks.sh"
  "scripts/open-terminal.sh"
  "scripts/migration-guard.sh"
  "scripts/lockfile-guard.sh"
  "scripts/auto-lint-notify.sh"
  "scripts/dtf.sh"
  "scripts/dtf-env.sh"
  "reviewers.json"
  "dtf-config.template.json"
  "CLAUDE.md.template"
  "company-config.example.json"
  "docs/integrations.md"
  "docs/learning-system.md"
  "docs/dev-workflow-checklist.md"
  "agents/architect.md"
  "agents/backend-dev.md"
  "agents/frontend-dev.md"
  "agents/pr-reviewer.md"
  "agents/data-engineer.md"
)

declare -a TRACKED_DIRS=(
  "skills/mermaid-diagram"
)

# Files to EXCLUDE from the public repo
declare -a PUBLIC_EXCLUDE=(
  "scripts/sync-config.sh"
)

# --- Sanitization: service names (both repos) ---
sanitize_service_names() {
  local f="$1"
  sed -i '' \
    -e 's/MedHelp/Repo/g' \
    -e 's/medhelp/repo/g' \
    -e 's/Absence/ServiceA/g' \
    -e 's/absence/service-a/g' \
    -e 's/HCM/ServiceB/g' \
    -e 's/hcm/service-b/g' \
    -e 's/IAM/ServiceC/g' \
    -e 's/iam/service-c/g' \
    -e 's/Messenger/ServiceD/g' \
    -e 's/messenger/service-d/g' \
    -e 's/Statistics/ServiceE/g' \
    -e 's/statistics/service-e/g' \
    -e 's/Lokalise/TranslationService/g' \
    -e 's/LOKALISE/TRANSLATION_SERVICE/g' \
    "$f"
}

# --- Sanitization: public-only (company references, usernames, ticket prefixes) ---
sanitize_public() {
  local f="$1"
  sed -i '' \
    -e 's/PLRS-/PROJ-/g' \
    -e 's/plrs-/proj-/g' \
    -e "s|johwer|your-username|g" \
    -e "s|-Users-johanwergelius|-Users-username|g" \
    -e 's/Insights Hub/Analytics Dashboard/g' \
    -e 's/medhelpcare\.atlassian\.net/your-company.atlassian.net/g' \
    -e 's/repocare\.atlassian\.net/your-company.atlassian.net/g' \
    "$f"
}

# --- Copy tracked files/dirs to a repo ---
copy_to_repo() {
  local repo_dir="$1"
  for file in "${TRACKED_FILES[@]}"; do
    local src="$CLAUDE_DIR/$file"
    local dst="$repo_dir/$file"
    [[ ! -f "$src" ]] && continue
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  done
  for dir in "${TRACKED_DIRS[@]}"; do
    local src="$CLAUDE_DIR/$dir"
    local dst="$repo_dir/$dir"
    [[ ! -d "$src" ]] && continue
    mkdir -p "$dst"
    rsync -a --exclude='.DS_Store' "$src/" "$dst/"
  done
}

# --- Apply sanitization to all tracked files/dirs in a repo ---
apply_sanitization() {
  local repo_dir="$1"
  shift
  # remaining args are sanitization function names
  for file in "${TRACKED_FILES[@]}"; do
    local dst="$repo_dir/$file"
    [[ ! -f "$dst" ]] && continue
    for fn in "$@"; do
      $fn "$dst"
    done
  done
  for dir in "${TRACKED_DIRS[@]}"; do
    local dst="$repo_dir/$dir"
    [[ ! -d "$dst" ]] && continue
    while IFS= read -r -d '' f; do
      for fn in "$@"; do
        $fn "$f"
      done
    done < <(find "$dst" -type f -not -name '.DS_Store' -print0)
  done
}

# --- Commit and push a repo ---
commit_and_push() {
  local repo_dir="$1"
  local repo_name="$2"
  cd "$repo_dir"
  if [[ -z "$(git status --porcelain)" ]]; then
    echo "[$repo_name] No changes detected."
    return 0
  fi
  echo "[$repo_name] Changed files:"
  git status --porcelain | while read -r line; do
    echo "  $line"
  done
  echo ""
  git add -A
  git commit -m "sync: update claude config files"
  git push
  echo "[$repo_name] Synced and pushed."
}

echo "=== Claude Config Sync ==="
echo ""

# --- 1. Private repo: exact copy, no sanitization ---
echo "--- Private repo (shared-claude-files) ---"
copy_to_repo "$PRIVATE_REPO"

# --- 2. Public repo: copy + sanitize service names + sanitize public ---
if [[ -d "$PUBLIC_REPO/.git" ]]; then
  echo "--- Public repo (dream-team-flow) ---"
  copy_to_repo "$PUBLIC_REPO"
  apply_sanitization "$PUBLIC_REPO" sanitize_service_names sanitize_public
  # Sanitize reviewers.json — replace GitHub usernames with generic placeholders
  if [[ -f "$PUBLIC_REPO/reviewers.json" ]]; then
    python3 -c "
import json, sys
with open(sys.argv[1]) as f: data = json.load(f)
for cat in data.get('categories', {}):
    data['categories'][cat] = [f'reviewer-{i+1}' for i, _ in enumerate(data['categories'][cat])]
with open(sys.argv[1], 'w') as f: json.dump(data, f, indent=2)
    " "$PUBLIC_REPO/reviewers.json"
  fi
  # Remove files that shouldn't be in the public repo
  for file in "${PUBLIC_EXCLUDE[@]}"; do
    rm -f "$PUBLIC_REPO/$file"
  done
else
  echo "Public repo not initialized, skipping."
fi

echo ""

# --- Detect GitHub account and switch if needed ---
CURRENT_GH_USER=$(gh api user -q '.login' 2>/dev/null || echo "")
NEED_SWITCH=false

if [[ "$CURRENT_GH_USER" != "$GH_USER" ]]; then
  echo "Switching GitHub account to $GH_USER..."
  gh auth switch --user "$GH_USER"
  NEED_SWITCH=true
fi

# --- Commit and push both repos ---
commit_and_push "$PRIVATE_REPO" "shared-claude-files"
echo ""
[[ -d "$PUBLIC_REPO/.git" ]] && commit_and_push "$PUBLIC_REPO" "dream-team-flow"

echo ""
echo "Done."

# Switch back to previous account if we changed it
if [[ "$NEED_SWITCH" == "true" && -n "$CURRENT_GH_USER" ]]; then
  echo "Switching back to $CURRENT_GH_USER..."
  gh auth switch --user "$CURRENT_GH_USER"
fi
