#!/bin/bash
# dtf — Dream Team Flow CLI
# Usage: dtf <command> [options]
#
# Commands:
#   install <REPO_URL> [--company-config <path>] [--to <dir>]  Install DTF from a repo
#   update                                                       Pull latest + verify
#   doctor                                                       Check installation health
#   contribute                                                   Export learnings as PR
#
# The --company-config flag points to a JSON file with real names for de-sanitization.
# If present, generic names (Repo, ServiceA, PROJ-) get replaced with real ones.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
DTF_CONFIG="$CLAUDE_DIR/dtf-config.json"
DTF_VERSION="1.0.0"

# Terminals supported
TERMINALS=("Alacritty" "Terminal" "iTerm" "Warp" "Kitty" "WezTerm" "Ghostty" "GNOME-Terminal" "Konsole" "Windows-Terminal")

# Directories to symlink
SYMLINK_DIRS=("commands" "scripts" "agents" "docs")
SYMLINK_SKILL_DIRS=("skills/mermaid-diagram")

# Files that are generated/merged, NOT symlinked
PERSONAL_FILES=("CLAUDE.md" "settings.json" "dtf-config.json")

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

info()  { echo "  $1"; }
ok()    { echo "  ✓ $1"; }
warn()  { echo "  ⚠ $1"; }
err()   { echo "  ✗ $1" >&2; }
header(){ echo ""; echo "=== $1 ==="; echo ""; }

ask() {
  local prompt="$1" default="$2" var="$3"
  if [[ -n "$default" ]]; then
    read -rp "  $prompt [$default]: " input
    eval "$var=\"${input:-$default}\""
  else
    read -rp "  $prompt: " input
    eval "$var=\"$input\""
  fi
}

ask_choice() {
  local prompt="$1" var="$2"
  shift 2
  local options=("$@")
  echo "  $prompt"
  for i in "${!options[@]}"; do
    echo "    $((i+1)). ${options[$i]}"
  done
  read -rp "  Choose [1]: " choice
  choice="${choice:-1}"
  local idx=$((choice - 1))
  if [[ $idx -ge 0 && $idx -lt ${#options[@]} ]]; then
    eval "$var=\"${options[$idx]}\""
  else
    eval "$var=\"${options[0]}\""
  fi
}

# ──────────────────────────────────────────────
# dtf install
# ──────────────────────────────────────────────

cmd_install() {
  local repo_url="" company_config="" install_dir=""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --company-config) company_config="$2"; shift 2 ;;
      --to) install_dir="$2"; shift 2 ;;
      -*) err "Unknown flag: $1"; exit 1 ;;
      *) repo_url="$1"; shift ;;
    esac
  done

  if [[ -z "$repo_url" ]]; then
    err "Usage: dtf install <REPO_URL> [--company-config <path>] [--to <dir>]"
    exit 1
  fi

  header "Dream Team Flow — Install"

  # 1. Clone repo
  if [[ -z "$install_dir" ]]; then
    install_dir="$HOME/dream-team-flow"
    ask "Where to clone the repo?" "$install_dir" install_dir
  fi

  if [[ -d "$install_dir/.git" ]]; then
    info "Repo already exists at $install_dir — pulling latest..."
    cd "$install_dir" && git pull
  else
    info "Cloning $repo_url → $install_dir..."
    git clone "$repo_url" "$install_dir"
  fi

  # 2. Apply company config (de-sanitization) if provided
  if [[ -n "$company_config" ]]; then
    if [[ ! -f "$company_config" ]]; then
      err "Company config not found: $company_config"
      exit 1
    fi
    header "Applying Company Config"
    apply_company_config "$install_dir" "$company_config"
  fi

  # 3. Interactive wizard for personal config
  header "Personal Setup"

  local user_name gh_user monorepo worktree_parent terminal

  ask "Your name" "" user_name
  ask "GitHub username" "" gh_user

  # Use company config defaults if available, otherwise generic defaults
  local default_monorepo="$HOME/Documents/Repo"
  local default_worktree="$HOME/Documents"
  if [[ -n "$company_config" && -f "$company_config" ]]; then
    local cc_monorepo=$(jq -r '.defaultPaths.monorepo // empty' "$company_config" | sed "s|~|$HOME|")
    local cc_worktree=$(jq -r '.defaultPaths.worktreeParent // empty' "$company_config" | sed "s|~|$HOME|")
    [[ -n "$cc_monorepo" ]] && default_monorepo="$cc_monorepo"
    [[ -n "$cc_worktree" ]] && default_worktree="$cc_worktree"
  fi

  ask "Path to your monorepo" "$default_monorepo" monorepo
  ask "Parent directory for worktrees" "$default_worktree" worktree_parent
  ask_choice "Preferred terminal" terminal "${TERMINALS[@]}"

  # 4. Ask about extra paths from company config
  local extra_paths_json="{}"
  if [[ -n "$company_config" && -f "$company_config" ]]; then
    local extra_keys
    extra_keys=$(jq -r '.extraPaths // {} | keys[]' "$company_config" 2>/dev/null || true)
    if [[ -n "$extra_keys" ]]; then
      header "Project-Specific Paths"
      info "Your company config defines additional paths. Set them for your machine:"
      echo ""
      while IFS= read -r key; do
        local desc=$(jq -r ".extraPaths[\"$key\"].description // \"$key\"" "$company_config")
        local default_val=$(jq -r ".extraPaths[\"$key\"].default // \"\"" "$company_config")
        local val
        ask "$desc" "$default_val" val
        extra_paths_json=$(echo "$extra_paths_json" | jq --arg k "$key" --arg v "$val" '. + {($k): $v}')
      done <<< "$extra_keys"
    fi
  fi

  # 5. Ask if user wants to add more custom paths
  echo ""
  local add_more="y"
  read -rp "  Add any custom paths? (y/N): " add_more
  while [[ "$add_more" =~ ^[yY] ]]; do
    local path_name path_value
    ask "Path name (e.g., 'dataDir', 'configDir')" "" path_name
    ask "Path value" "" path_value
    if [[ -n "$path_name" && -n "$path_value" ]]; then
      extra_paths_json=$(echo "$extra_paths_json" | jq --arg k "$path_name" --arg v "$path_value" '. + {($k): $v}')
      ok "Added: $path_name = $path_value"
    fi
    read -rp "  Add another? (y/N): " add_more
  done

  # 6. Write dtf-config.json
  mkdir -p "$CLAUDE_DIR"
  cat > "$DTF_CONFIG" << EOF
{
  "version": 1,
  "user": {
    "name": "$user_name",
    "githubUsername": "$gh_user"
  },
  "paths": {
    "monorepo": "$monorepo",
    "worktreeParent": "$worktree_parent",
    "workflowRepo": "$install_dir"
  },
  "extraPaths": $extra_paths_json,
  "terminal": "$terminal"
}
EOF
  ok "Config written to $DTF_CONFIG"

  # 5. Create symlinks
  header "Creating Symlinks"
  create_symlinks "$install_dir"

  # 6. Merge settings.json
  header "Merging Settings"
  merge_settings "$install_dir"

  # 7. Generate CLAUDE.md from template
  header "Generating CLAUDE.md"
  generate_claude_md "$install_dir" "$monorepo" "$terminal"

  # 8. Add dtf to PATH
  header "Adding dtf to PATH"
  local bin_dir="$HOME/bin"
  mkdir -p "$bin_dir"
  ln -sf "$install_dir/scripts/dtf.sh" "$bin_dir/dtf"
  chmod +x "$install_dir/scripts/dtf.sh"
  ok "Linked dtf → $bin_dir/dtf"

  if ! echo "$PATH" | grep -q "$bin_dir"; then
    warn "Add to your shell profile: export PATH=\"\$HOME/bin:\$PATH\""
  fi

  header "Installation Complete"
  info "Run 'dtf doctor' to verify everything is set up correctly."
  info "Run 'dtf update' anytime to pull the latest workflow changes."
}

apply_company_config() {
  local repo_dir="$1" config="$2"

  # Read name mappings from company-config.json
  local project_name=$(jq -r '.projectName // empty' "$config")
  local jira_domain=$(jq -r '.jiraDomain // empty' "$config")
  local ticket_prefix=$(jq -r '.ticketPrefix // empty' "$config")

  # Build sed arguments for service name replacements
  local sed_args=()

  if [[ -n "$project_name" ]]; then
    sed_args+=(-e "s/Repo/$project_name/g" -e "s/repo/${project_name,,}/g")
    info "Repo → $project_name"
  fi

  if [[ -n "$ticket_prefix" ]]; then
    sed_args+=(-e "s/PROJ-/$ticket_prefix-/g" -e "s/proj-/${ticket_prefix,,}-/g")
    info "PROJ- → $ticket_prefix-"
  fi

  if [[ -n "$jira_domain" ]]; then
    sed_args+=(-e "s/your-company.atlassian.net/$jira_domain/g")
    info "your-company.atlassian.net → $jira_domain"
  fi

  # Read service name mappings
  local services
  services=$(jq -r '.services // {} | to_entries[] | "\(.key)=\(.value)"' "$config" 2>/dev/null || true)
  while IFS='=' read -r generic real; do
    [[ -z "$generic" ]] && continue
    local generic_lower="${generic,,}"
    local real_lower="${real,,}"
    # Convert camelCase generic to kebab-case for lowercase version
    local generic_kebab=$(echo "$generic_lower" | sed 's/\([a-z]\)\([A-Z]\)/\1-\2/g' | tr '[:upper:]' '[:lower:]')
    sed_args+=(-e "s/$generic/$real/g" -e "s/$generic_kebab/$real_lower/g")
    info "$generic → $real"
  done <<< "$services"

  # Username replacement
  local gh_username
  gh_username=$(jq -r '.githubUsername // empty' "$config")
  if [[ -n "$gh_username" ]]; then
    sed_args+=(-e "s/your-username/$gh_username/g")
    info "your-username → $gh_username"
  fi

  if [[ ${#sed_args[@]} -eq 0 ]]; then
    info "No replacements to apply."
    return
  fi

  # Apply to all text files in the repo (skip .git, images, etc.)
  local count=0
  while IFS= read -r -d '' f; do
    if file "$f" | grep -q text; then
      sed -i '' "${sed_args[@]}" "$f" 2>/dev/null || true
      count=$((count + 1))
    fi
  done < <(find "$repo_dir" -not -path '*/.git/*' -type f -print0)

  ok "Applied de-sanitization to $count files"
}

create_symlinks() {
  local repo_dir="$1"

  for dir in "${SYMLINK_DIRS[@]}"; do
    local src="$repo_dir/$dir"
    local dst="$CLAUDE_DIR/$dir"

    if [[ ! -d "$src" ]]; then
      warn "Source directory not found: $src"
      continue
    fi

    mkdir -p "$dst"

    # Symlink each file individually (not the directory) to allow personal files too
    for f in "$src"/*; do
      [[ ! -f "$f" ]] && continue
      local basename=$(basename "$f")
      local target="$dst/$basename"

      # Skip personal files
      local skip=false
      for pf in "${PERSONAL_FILES[@]}"; do
        [[ "$basename" == "$pf" ]] && skip=true
      done
      $skip && continue

      # Remove existing file/symlink
      [[ -e "$target" || -L "$target" ]] && rm -f "$target"
      ln -s "$f" "$target"
    done
    ok "$dir/ — $(ls -1 "$src" | wc -l | tr -d ' ') files linked"
  done

  # Symlink skill directories
  for dir in "${SYMLINK_SKILL_DIRS[@]}"; do
    local src="$repo_dir/$dir"
    local dst="$CLAUDE_DIR/$dir"

    if [[ ! -d "$src" ]]; then
      continue
    fi

    mkdir -p "$(dirname "$dst")"
    [[ -e "$dst" || -L "$dst" ]] && rm -rf "$dst"
    ln -s "$src" "$dst"
    ok "$dir/ — linked"
  done
}

merge_settings() {
  local repo_dir="$1"
  local repo_settings="$repo_dir/settings.json"
  local user_settings="$CLAUDE_DIR/settings.json"

  if [[ ! -f "$repo_settings" ]]; then
    warn "No settings.json in repo"
    return
  fi

  if [[ ! -f "$user_settings" ]]; then
    cp "$repo_settings" "$user_settings"
    ok "Created settings.json from repo"
    return
  fi

  # Deep merge: repo values as base, user values override
  # But for hooks arrays, concatenate (no duplicates by command)
  local merged
  merged=$(jq -s '
    .[0] as $repo | .[1] as $user |
    ($repo * $user) |
    .hooks = (
      ($repo.hooks // {}) | to_entries | map(
        .key as $event |
        .value as $repo_hooks |
        ($user.hooks[$event] // []) as $user_hooks |
        {
          key: $event,
          value: (
            $repo_hooks + [$user_hooks[] | select(
              . as $uh | [$repo_hooks[] | select(.hooks[0].command == $uh.hooks[0].command)] | length == 0
            )]
          )
        }
      ) | from_entries
    )
  ' "$repo_settings" "$user_settings" 2>/dev/null || cat "$user_settings")

  echo "$merged" > "$user_settings"
  ok "Merged settings.json (hooks preserved)"
}

generate_claude_md() {
  local repo_dir="$1" monorepo="$2" terminal="$3"
  local template="$repo_dir/CLAUDE.md.template"
  local output="$CLAUDE_DIR/CLAUDE.md"

  if [[ ! -f "$template" ]]; then
    warn "No CLAUDE.md.template in repo — skipping CLAUDE.md generation"
    return
  fi

  sed \
    -e "s|{{MONOREPO_PATH}}|$monorepo|g" \
    -e "s|{{TERMINAL}}|$terminal|g" \
    "$template" > "$output"

  ok "Generated CLAUDE.md with monorepo=$monorepo, terminal=$terminal"
}

# ──────────────────────────────────────────────
# dtf update
# ──────────────────────────────────────────────

cmd_update() {
  if [[ ! -f "$DTF_CONFIG" ]]; then
    err "DTF not installed. Run: dtf install <REPO_URL>"
    exit 1
  fi

  source "$CLAUDE_DIR/scripts/dtf-env.sh"

  if [[ -z "$DTF_WORKFLOW_REPO" || ! -d "$DTF_WORKFLOW_REPO" ]]; then
    err "Workflow repo not found at: $DTF_WORKFLOW_REPO"
    exit 1
  fi

  header "Dream Team Flow — Update"

  # Record current hash
  local old_hash
  old_hash=$(cd "$DTF_WORKFLOW_REPO" && git rev-parse HEAD)

  # Pull latest
  info "Pulling latest..."
  cd "$DTF_WORKFLOW_REPO" && git pull

  local new_hash
  new_hash=$(git rev-parse HEAD)

  if [[ "$old_hash" == "$new_hash" ]]; then
    ok "Already up to date."
  else
    info "Changes since last update:"
    git log --oneline "${old_hash}..${new_hash}"
  fi

  # Verify symlinks
  info "Verifying symlinks..."
  create_symlinks "$DTF_WORKFLOW_REPO"

  # Re-merge settings
  merge_settings "$DTF_WORKFLOW_REPO"

  # Re-generate CLAUDE.md
  generate_claude_md "$DTF_WORKFLOW_REPO" "$DTF_MONOREPO" "$DTF_TERMINAL"

  header "Update Complete"
}

# ──────────────────────────────────────────────
# dtf doctor
# ──────────────────────────────────────────────

cmd_doctor() {
  header "Dream Team Flow — Doctor"
  local issues=0

  # Check config
  if [[ -f "$DTF_CONFIG" ]]; then
    ok "dtf-config.json exists"
    source "$CLAUDE_DIR/scripts/dtf-env.sh"
  else
    err "dtf-config.json not found — run: dtf install <REPO_URL>"
    issues=$((issues + 1))
  fi

  # Check workflow repo
  if [[ -n "$DTF_WORKFLOW_REPO" && -d "$DTF_WORKFLOW_REPO/.git" ]]; then
    ok "Workflow repo: $DTF_WORKFLOW_REPO"
  elif [[ -n "$DTF_WORKFLOW_REPO" ]]; then
    err "Workflow repo not found: $DTF_WORKFLOW_REPO"
    issues=$((issues + 1))
  fi

  # Check monorepo
  if [[ -n "$DTF_MONOREPO" && -d "$DTF_MONOREPO" ]]; then
    ok "Monorepo: $DTF_MONOREPO"
  elif [[ -n "$DTF_MONOREPO" ]]; then
    warn "Monorepo not found: $DTF_MONOREPO"
  fi

  # Check required tools
  for tool in jq tmux gh git; do
    if command -v "$tool" &>/dev/null; then
      ok "$tool installed"
    else
      err "$tool not found — install it"
      issues=$((issues + 1))
    fi
  done

  # Check optional tools
  for tool in acli; do
    if command -v "$tool" &>/dev/null; then
      ok "$tool installed (optional)"
    else
      warn "$tool not found (optional — needed for Jira integration)"
    fi
  done

  # Check symlinks
  if [[ -n "$DTF_WORKFLOW_REPO" ]]; then
    local broken=0
    for dir in "${SYMLINK_DIRS[@]}"; do
      if [[ -d "$CLAUDE_DIR/$dir" ]]; then
        for f in "$CLAUDE_DIR/$dir"/*; do
          if [[ -L "$f" && ! -e "$f" ]]; then
            err "Broken symlink: $f"
            broken=$((broken + 1))
          fi
        done
      fi
    done
    if [[ $broken -eq 0 ]]; then
      ok "All symlinks intact"
    else
      issues=$((issues + broken))
    fi
  fi

  # Check CLAUDE.md exists
  if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
    ok "CLAUDE.md exists"
  else
    warn "CLAUDE.md not found — run: dtf update"
  fi

  # Check terminal
  if [[ -n "$DTF_TERMINAL" ]]; then
    ok "Terminal: $DTF_TERMINAL"
  fi

  echo ""
  if [[ $issues -eq 0 ]]; then
    echo "  All checks passed. Dream Team Flow is healthy."
  else
    echo "  Found $issues issue(s). Fix them and run 'dtf doctor' again."
  fi
}

# ──────────────────────────────────────────────
# dtf contribute
# ──────────────────────────────────────────────

cmd_contribute() {
  if [[ ! -f "$DTF_CONFIG" ]]; then
    err "DTF not installed. Run: dtf install <REPO_URL>"
    exit 1
  fi

  source "$CLAUDE_DIR/scripts/dtf-env.sh"

  header "Dream Team Flow — Contribute Learnings"

  # Find the memory directory
  local memory_dir=""
  for dir in "$HOME"/.claude/projects/*/memory; do
    if [[ -f "$dir/dream-team-learnings.md" ]]; then
      memory_dir="$dir"
      break
    fi
  done

  if [[ -z "$memory_dir" ]]; then
    err "No dream-team-learnings.md found in any project memory directory."
    exit 1
  fi

  local learnings="$memory_dir/dream-team-learnings.md"
  local username="${DTF_GH_USER:-$(whoami)}"
  local date=$(date +%Y-%m-%d)
  local branch="learnings/${username}-${date}"
  local contrib_file="learnings/contributions/${username}-${date}.md"

  info "Source: $learnings"
  info "Branch: $branch"

  cd "$DTF_WORKFLOW_REPO"

  # Create learnings directory if needed
  mkdir -p "learnings/contributions"

  # Create branch and copy learnings
  git checkout -b "$branch" 2>/dev/null || git checkout "$branch"
  cp "$learnings" "$contrib_file"

  # Add attribution header
  local tmp=$(mktemp)
  echo "# Learnings from $username — $date" > "$tmp"
  echo "" >> "$tmp"
  cat "$contrib_file" >> "$tmp"
  mv "$tmp" "$contrib_file"

  git add "$contrib_file"
  git commit -m "learnings: add session learnings from $username ($date)"

  info "Pushing branch..."
  git push -u origin "$branch"

  # Open PR
  if command -v gh &>/dev/null; then
    gh pr create \
      --title "Learnings: $username ($date)" \
      --body "Session learnings contributed by $username on $date. Review and curate into aggregated-learnings.md." \
      --head "$branch"
    ok "PR created!"
  else
    warn "gh not installed — push the branch and create a PR manually."
  fi

  # Return to main
  git checkout main 2>/dev/null || git checkout master
}

# ──────────────────────────────────────────────
# Main dispatcher
# ──────────────────────────────────────────────

cmd="${1:-help}"
shift 2>/dev/null || true

case "$cmd" in
  install)    cmd_install "$@" ;;
  update)     cmd_update "$@" ;;
  doctor)     cmd_doctor "$@" ;;
  contribute) cmd_contribute "$@" ;;
  version)    echo "dtf v$DTF_VERSION" ;;
  help|--help|-h)
    echo "dtf — Dream Team Flow CLI v$DTF_VERSION"
    echo ""
    echo "Commands:"
    echo "  install <REPO_URL> [--company-config <path>] [--to <dir>]"
    echo "    Clone repo, run setup wizard, create symlinks"
    echo ""
    echo "  update"
    echo "    Pull latest changes, verify symlinks, regenerate CLAUDE.md"
    echo ""
    echo "  doctor"
    echo "    Check installation health"
    echo ""
    echo "  contribute"
    echo "    Export your session learnings as a PR to the workflow repo"
    echo ""
    echo "  version"
    echo "    Show version"
    ;;
  *)
    err "Unknown command: $cmd"
    echo "Run 'dtf help' for usage."
    exit 1
    ;;
esac
