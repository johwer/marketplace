#!/bin/bash
# dtf — Dream Team Flow CLI
# Usage: dtf <command> [options]
#
# Commands:
#   install <REPO_URL> [--company-config <path>] [--to <dir>]  Install DTF from a repo
#   update                                                       Pull latest + verify
#   configure                                                    Set/change role and workflow steps
#   steps <list|add|remove|reset>                                Manage workflow steps
#   apply-config <path-to-company-config.json> [--update]        Apply company config after install
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

# Roles: display|key pairs (pipe-separated to avoid associative array issues)
ROLE_COUNT=12
ROLE_DISPLAY=("Developer (Frontend)" "Developer (Backend)" "Developer (Fullstack)" "Data Engineer" "Data Analyst" "Infrastructure / DevOps" "QA / Tester (E2E, automation)" "UAT / QA Stakeholder (staging testing, no code)" "Product Owner" "Sales" "Marketing" "Customer Operations")
ROLE_KEY=("frontend-dev" "backend-dev" "fullstack-dev" "data-engineer" "data-analyst" "infra" "tester" "uat-tester" "po" "sales" "marketing" "customer-ops")

# Lookup functions for role config (avoids declare -A compatibility issues)
get_role_agents() {
  case "$1" in
    frontend-dev)  echo "engineering/frontend-dev engineering/architect engineering/pr-reviewer engineering/api-designer design/ui-designer" ;;
    backend-dev)   echo "engineering/backend-dev engineering/architect engineering/pr-reviewer engineering/api-designer engineering/migration-planner" ;;
    fullstack-dev) echo "engineering/frontend-dev engineering/backend-dev engineering/architect engineering/pr-reviewer engineering/api-designer engineering/performance-analyst engineering/migration-planner" ;;
    data-engineer) echo "data/data-engineer data/pipeline-builder data/insights-reporter engineering/architect" ;;
    data-analyst)  echo "data/data-analyst data/insights-reporter" ;;
    infra)         echo "infrastructure/infra-engineer infrastructure/ci-cd-engineer infrastructure/security-auditor" ;;
    tester)        echo "testing/qa-tester testing/api-tester testing/performance-benchmarker" ;;
    uat-tester)    echo "testing/uat-tester" ;;
    po)            echo "product/po-analyst product/requirements-analyst product/sprint-prioritizer engineering/architect" ;;
    sales)         echo "marketing/sales-enablement data/data-analyst data/insights-reporter" ;;
    marketing)     echo "marketing/marketing-ops marketing/content-creator marketing/social-strategist" ;;
    customer-ops)  echo "operations/customer-ops operations/support-responder" ;;
    *)             echo "" ;;
  esac
}

get_role_skills() {
  case "$1" in
    frontend-dev)  echo "frontend-conventions frontend-performance tdd playwright-cli visual-development-workflow mermaid-diagram code-insights" ;;
    backend-dev)   echo "backend-conventions backend-performance tdd mermaid-diagram code-insights" ;;
    fullstack-dev) echo "frontend-conventions backend-conventions frontend-performance backend-performance tdd playwright-cli visual-development-workflow mermaid-diagram data-conventions code-insights" ;;
    data-engineer) echo "data-conventions data-analysis-workflows mermaid-diagram" ;;
    data-analyst)  echo "data-analysis-workflows" ;;
    infra)         echo "infra-conventions aws-performance" ;;
    tester)        echo "testing-workflows playwright-cli" ;;
    uat-tester)    echo "uat-workflows" ;;
    po)            echo "po-workflows mermaid-diagram" ;;
    sales)         echo "presentation-workflows" ;;
    marketing)     echo "content-workflows" ;;
    customer-ops)  echo "" ;;
    *)             echo "" ;;
  esac
}

get_role_external_skills() {
  case "$1" in
    data-engineer) echo "AltimateAI/data-engineering-skills (dbt models, Snowflake optimization)" ;;
    data-analyst)  echo "AltimateAI/data-engineering-skills (dbt + SQL skills)" ;;
    infra)         printf "LukasNiessen/terrashark (Terraform failure-mode skill)\nterramate-io/agent-skills (37 Terraform rules)\na-pavithraa/aws-serverless-skill (Lambda, DynamoDB, API Gateway)" ;;
    tester)        printf "PramodDutta/qaskills (20+ QA skills)\nproffesor-for-testing/agentic-qe (AI-powered test generation)\nsharmasundip/playwright-qa-skills (no-code recording)" ;;
    *)             echo "" ;;
  esac
}

get_role_default_steps() {
  case "$1" in
    frontend-dev)  echo '[{"name":"ESLint check","type":"automated","command":"npm run lint","when":"before-commit"},{"name":"Code insights (quick nudges + DTO analysis)","type":"reminder","when":"before-push"},{"name":"Visual verification","type":"reminder","when":"before-pr"},{"name":"Screenshot capture","type":"reminder","when":"before-pr"},{"name":"Accessibility check","type":"reminder","when":"before-pr"}]' ;;
    backend-dev)   echo '[{"name":"CSharpier format","type":"automated","command":"dotnet csharpier .","when":"before-commit"},{"name":"Run unit tests","type":"automated","command":"dotnet test","when":"before-push"},{"name":"Code insights (quick nudges + DTO analysis)","type":"reminder","when":"before-push"},{"name":"Swagger validation","type":"reminder","when":"before-pr"}]' ;;
    fullstack-dev) echo '[{"name":"ESLint check","type":"automated","command":"npm run lint","when":"before-commit"},{"name":"CSharpier format","type":"automated","command":"dotnet csharpier .","when":"before-commit"},{"name":"Run all tests","type":"automated","command":"dotnet test && npm run test","when":"before-push"},{"name":"Code insights (quick nudges + DTO analysis)","type":"reminder","when":"before-push"},{"name":"Visual verification","type":"reminder","when":"before-pr"},{"name":"Screenshot capture","type":"reminder","when":"before-pr"}]' ;;
    data-engineer) echo '[{"name":"dbt build","type":"automated","command":"dbt build","when":"before-push"},{"name":"dbt test","type":"automated","command":"dbt test","when":"before-push"},{"name":"SQL review","type":"reminder","when":"before-pr"}]' ;;
    data-analyst)  echo '[{"name":"Notebook outputs cleared","type":"reminder","when":"before-commit"},{"name":"SQL queries documented","type":"reminder","when":"before-push"},{"name":"Findings summarized","type":"reminder","when":"before-pr"}]' ;;
    infra)         echo '[{"name":"terraform fmt","type":"automated","command":"terraform fmt -check -recursive infra/","when":"before-commit"},{"name":"terraform validate","type":"automated","command":"cd infra && terraform validate","when":"before-commit"},{"name":"No secrets in code","type":"reminder","when":"before-commit"},{"name":"terraform plan","type":"automated","command":"bash ~/.claude/scripts/terraform-plan-summary.sh","when":"before-push"},{"name":"WAF rules: rate limits set","type":"reminder","when":"before-pr"},{"name":"Monitoring: alarms + Slack channel","type":"reminder","when":"before-pr"},{"name":"Tags on all resources","type":"reminder","when":"before-pr"},{"name":"GH Actions workflows verified","type":"automated","command":"bash ~/.claude/scripts/verify-infra-workflows.sh","when":"before-pr"}]' ;;
    tester)        echo '[{"name":"Test plan documented","type":"reminder","when":"on-start"},{"name":"All tests passing","type":"automated","command":"npm run test:e2e","when":"before-pr"},{"name":"Coverage report reviewed","type":"reminder","when":"before-pr"}]' ;;
    uat-tester)    echo '[{"name":"Acceptance criteria listed","type":"reminder","when":"on-start"},{"name":"All user roles tested","type":"reminder","when":"before-pr"},{"name":"Permission matrix verified","type":"reminder","when":"before-pr"},{"name":"Bug reports filed","type":"reminder","when":"after-pr"}]' ;;
    po)            echo '[{"name":"Impact analysis done","type":"reminder","when":"on-start"},{"name":"Acceptance criteria written","type":"reminder","when":"before-pr"},{"name":"Stakeholders notified","type":"reminder","when":"after-pr"}]' ;;
    sales)         echo '[{"name":"Data sources verified","type":"reminder","when":"on-start"},{"name":"ROI calculated","type":"reminder","when":"before-pr"},{"name":"Customer-specific data checked","type":"reminder","when":"before-pr"}]' ;;
    marketing)     echo '[{"name":"SEO keywords checked","type":"reminder","when":"before-push"},{"name":"Multi-language considered","type":"reminder","when":"before-pr"},{"name":"Brand voice reviewed","type":"reminder","when":"before-pr"}]' ;;
    customer-ops)  echo '[{"name":"Mapping validated","type":"reminder","when":"before-push"},{"name":"Existing customer patterns checked","type":"reminder","when":"on-start"},{"name":"Acceptance test in staging","type":"reminder","when":"before-pr"}]' ;;
    *)             echo '[]' ;;
  esac
}

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
  local input=""
  if [[ -n "$default" ]]; then
    read -rp "  $prompt [$default]: " input
    printf -v "$var" '%s' "${input:-$default}"
  else
    read -rp "  $prompt: " input
    printf -v "$var" '%s' "$input"
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
  local choice=""
  read -rp "  Choose [1]: " choice
  choice="${choice:-1}"
  local idx=$((choice - 1))
  if [[ $idx -ge 0 && $idx -lt ${#options[@]} ]]; then
    printf -v "$var" '%s' "${options[$idx]}"
  else
    printf -v "$var" '%s' "${options[0]}"
  fi
}

# Ask for role and set role_display + role_key
ask_role() {
  echo "  What's your primary role?"
  for i in "${!ROLE_DISPLAY[@]}"; do
    echo "    $((i+1)). ${ROLE_DISPLAY[$i]}"
  done
  read -rp "  Choose [1]: " choice
  choice="${choice:-1}"
  local idx=$((choice - 1))
  if [[ $idx -ge 0 && $idx -lt $ROLE_COUNT ]]; then
    role_display="${ROLE_DISPLAY[$idx]}"
    role_key="${ROLE_KEY[$idx]}"
  else
    role_display="${ROLE_DISPLAY[0]}"
    role_key="${ROLE_KEY[0]}"
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

  # 3b. Ask about role
  echo ""
  local role_display="" role_key=""
  ask_role
  ok "Role: $role_display ($role_key)"

  # Show recommended external skills for this role
  local ext_skills
  ext_skills=$(get_role_external_skills "$role_key")
  if [[ -n "$ext_skills" ]]; then
    echo ""
    info "Recommended external skills for your role:"
    echo -e "$ext_skills" | while IFS= read -r skill; do
      [[ -n "$skill" ]] && info "  → $skill"
    done
    echo ""
    info "You can install these later. See ~/.claude/docs/dtf-roles.md for install commands."
  fi

  # 3c. Configure workflow steps
  local default_steps
  default_steps=$(get_role_default_steps "$role_key")
  local workflow_steps="$default_steps"

  if [[ "$default_steps" != "[]" ]]; then
    echo ""
    header "Workflow Steps"
    info "Default steps for your role:"
    echo "$default_steps" | jq -r '.[] | "  [\(.when)] \(.name) (\(.type))"'
    echo ""

    local customize_steps
    read -rp "  Customize these steps? (y/N): " customize_steps
    if [[ "$customize_steps" =~ ^[yY] ]]; then
      # Let user remove steps
      local step_count
      step_count=$(echo "$default_steps" | jq 'length')
      info "Enter step numbers to REMOVE (comma-separated), or press Enter to keep all:"
      for i in $(seq 0 $((step_count - 1))); do
        local step_name step_when step_type
        step_name=$(echo "$default_steps" | jq -r ".[$i].name")
        step_when=$(echo "$default_steps" | jq -r ".[$i].when")
        step_type=$(echo "$default_steps" | jq -r ".[$i].type")
        echo "    $((i+1)). [$step_when] $step_name ($step_type)"
      done
      local remove_indices
      read -rp "  Remove: " remove_indices

      if [[ -n "$remove_indices" ]]; then
        # Build jq filter to remove selected indices (convert 1-based to 0-based)
        local jq_filter="[.[] | select(false"
        workflow_steps="$default_steps"
        for idx in $(echo "$remove_indices" | tr ',' ' '); do
          idx=$((idx - 1))
          workflow_steps=$(echo "$workflow_steps" | jq "del(.[$idx])")
        done
        # Re-index after deletion (jq handles this automatically)
      fi

      # Let user add custom steps
      local add_custom
      read -rp "  Add custom steps? (y/N): " add_custom
      while [[ "$add_custom" =~ ^[yY] ]]; do
        local step_name step_type step_when step_command=""
        ask "Step name" "" step_name
        ask_choice "Step type" step_type "reminder" "automated"
        if [[ "$step_type" == "automated" ]]; then
          ask "Shell command to run" "" step_command
        fi
        ask_choice "When to trigger" step_when "before-commit" "before-push" "before-pr" "after-pr" "on-start"

        if [[ "$step_type" == "automated" ]]; then
          workflow_steps=$(echo "$workflow_steps" | jq \
            --arg n "$step_name" --arg t "$step_type" --arg c "$step_command" --arg w "$step_when" \
            '. + [{"name":$n,"type":$t,"command":$c,"when":$w}]')
        else
          workflow_steps=$(echo "$workflow_steps" | jq \
            --arg n "$step_name" --arg t "$step_type" --arg w "$step_when" \
            '. + [{"name":$n,"type":$t,"when":$w}]')
        fi
        ok "Added: [$step_when] $step_name ($step_type)"
        read -rp "  Add another step? (y/N): " add_custom
      done
    fi
  else
    # No default steps — offer to add custom ones
    echo ""
    local add_custom
    read -rp "  Add custom workflow steps? (y/N): " add_custom
    while [[ "$add_custom" =~ ^[yY] ]]; do
      local step_name step_type step_when step_command=""
      ask "Step name" "" step_name
      ask_choice "Step type" step_type "reminder" "automated"
      if [[ "$step_type" == "automated" ]]; then
        ask "Shell command to run" "" step_command
      fi
      ask_choice "When to trigger" step_when "before-commit" "before-push" "before-pr" "after-pr" "on-start"

      if [[ "$step_type" == "automated" ]]; then
        workflow_steps=$(echo "$workflow_steps" | jq \
          --arg n "$step_name" --arg t "$step_type" --arg c "$step_command" --arg w "$step_when" \
          '. + [{"name":$n,"type":$t,"command":$c,"when":$w}]')
      else
        workflow_steps=$(echo "$workflow_steps" | jq \
          --arg n "$step_name" --arg t "$step_type" --arg w "$step_when" \
          '. + [{"name":$n,"type":$t,"when":$w}]')
      fi
      ok "Added: [$step_when] $step_name ($step_type)"
      read -rp "  Add another step? (y/N): " add_custom
    done
  fi

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

  # Resolve company config to absolute path if provided
  local abs_company_config=""
  if [[ -n "$company_config" && -f "$company_config" ]]; then
    abs_company_config=$(cd "$(dirname "$company_config")" && echo "$(pwd)/$(basename "$company_config")")
  fi

  # Build role config
  local role_agents
  role_agents=$(get_role_agents "$role_key")
  local role_skills
  role_skills=$(get_role_skills "$role_key")

  # Convert space-separated lists to JSON arrays
  local agents_json="[]"
  if [[ -n "$role_agents" ]]; then
    agents_json=$(echo "$role_agents" | tr ' ' '\n' | jq -R . | jq -s .)
  fi
  local skills_json="[]"
  if [[ -n "$role_skills" ]]; then
    skills_json=$(echo "$role_skills" | tr ' ' '\n' | jq -R . | jq -s .)
  fi

  # Format workflow steps (compact)
  local steps_json
  steps_json=$(echo "$workflow_steps" | jq -c '.')

  cat > "$DTF_CONFIG" << EOF
{
  "version": 2,
  "user": {
    "name": "$user_name",
    "githubUsername": "$gh_user"
  },
  "role": "$role_key",
  "roleConfig": {
    "displayName": "$role_display",
    "agents": $agents_json,
    "skills": $skills_json
  },
  "workflowSteps": $(echo "$workflow_steps" | jq '.'),
  "paths": {
    "monorepo": "$monorepo",
    "worktreeParent": "$worktree_parent",
    "workflowRepo": "$install_dir"
  },
  "extraPaths": $extra_paths_json,
  "terminal": "$terminal"
}
EOF

  # Add companyConfig field if provided (use jq to keep valid JSON)
  if [[ -n "$abs_company_config" ]]; then
    local tmp
    tmp=$(jq --arg p "$abs_company_config" '.companyConfig = $p' "$DTF_CONFIG")
    echo "$tmp" > "$DTF_CONFIG"
  fi

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

    # Symlink files in top-level directory
    local file_count=0
    for f in "$src"/*; do
      if [[ -f "$f" ]]; then
        local basename=$(basename "$f")
        local target="$dst/$basename"

        # Skip personal files
        local skip=false
        for pf in "${PERSONAL_FILES[@]}"; do
          [[ "$basename" == "$pf" ]] && skip=true
        done
        $skip && continue

        [[ -e "$target" || -L "$target" ]] && rm -f "$target"
        ln -s "$f" "$target"
        file_count=$((file_count + 1))
      fi
    done

    # Symlink subdirectories (e.g., agents/engineering/, agents/product/)
    for subdir in "$src"/*/; do
      [[ ! -d "$subdir" ]] && continue
      local subdir_name=$(basename "$subdir")
      local dst_subdir="$dst/$subdir_name"

      mkdir -p "$dst_subdir"
      for f in "$subdir"*; do
        [[ ! -f "$f" ]] && continue
        local basename=$(basename "$f")
        local target="$dst_subdir/$basename"
        [[ -e "$target" || -L "$target" ]] && rm -f "$target"
        ln -s "$f" "$target"
        file_count=$((file_count + 1))
      done
    done

    ok "$dir/ — $file_count files linked"
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
  local dtf_start="<!-- DTF:START -->"
  local dtf_end="<!-- DTF:END -->"

  if [[ ! -f "$template" ]]; then
    warn "No CLAUDE.md.template in repo — skipping CLAUDE.md generation"
    return
  fi

  # Render template with personal values
  local rendered
  rendered=$(sed \
    -e "s|{{MONOREPO_PATH}}|$monorepo|g" \
    -e "s|{{TERMINAL}}|$terminal|g" \
    "$template")

  local dtf_block
  dtf_block=$(printf '%s\n%s\n%s' "$dtf_start" "$rendered" "$dtf_end")

  if [[ ! -f "$output" ]]; then
    # Fresh install — write DTF block + personal section placeholder
    printf '%s\n\n## Personal\n\n<!-- Add your personal customizations below. DTF will never touch this section. -->\n' \
      "$dtf_block" > "$output"
    ok "Generated CLAUDE.md"
  elif grep -q "$dtf_start" "$output"; then
    # Existing file with DTF section — replace only between markers
    local before after
    before=$(sed "/$dtf_start/,\$d" "$output")
    after=$(sed "1,/$dtf_end/d" "$output")
    printf '%s%s\n%s' "$before" "$dtf_block" "$after" > "$output"
    ok "Merged CLAUDE.md (DTF section updated, personal content preserved)"
  else
    # Existing file without markers — prepend DTF block, keep rest as personal
    local existing
    existing=$(cat "$output")
    printf '%s\n\n%s' "$dtf_block" "$existing" > "$output"
    ok "Merged CLAUDE.md (DTF section prepended, existing content preserved)"
  fi
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

  # Check company config
  local cc_path
  cc_path=$(jq -r '.companyConfig // empty' "$DTF_CONFIG" 2>/dev/null || true)
  if [[ -n "$cc_path" ]]; then
    if [[ -f "$cc_path" ]]; then
      ok "Company config: $cc_path"
    else
      warn "Company config not found at: $cc_path (file moved?)"
    fi
  else
    info "No company config applied — run: dtf apply-config <path>"
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

  # Check performance tools
  if command -v eslint_d &>/dev/null; then
    ok "eslint_d installed (10x faster ESLint in quality-gate.sh)"
  else
    warn "eslint_d not found (optional — install: npm install -g eslint_d)"
  fi

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
# dtf apply-config
# ──────────────────────────────────────────────

cmd_apply_config() {
  if [[ ! -f "$DTF_CONFIG" ]]; then
    err "DTF not installed. Run: dtf install <REPO_URL>"
    exit 1
  fi

  source "$CLAUDE_DIR/scripts/dtf-env.sh"

  local company_config="" do_update=false

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --update) do_update=true; shift ;;
      -*) err "Unknown flag: $1"; exit 1 ;;
      *) company_config="$1"; shift ;;
    esac
  done

  if [[ -z "$company_config" ]]; then
    err "Usage: dtf apply-config <path-to-company-config.json> [--update]"
    exit 1
  fi

  if [[ ! -f "$company_config" ]]; then
    err "Company config not found: $company_config"
    exit 1
  fi

  if [[ -z "$DTF_WORKFLOW_REPO" || ! -d "$DTF_WORKFLOW_REPO" ]]; then
    err "Workflow repo not found at: $DTF_WORKFLOW_REPO"
    exit 1
  fi

  header "Dream Team Flow — Apply Company Config"

  # Optionally pull latest first
  if $do_update; then
    info "Pulling latest..."
    cd "$DTF_WORKFLOW_REPO" && git pull
    ok "Repo updated"
  fi

  # Save company config path (absolute) in dtf-config.json for reference
  local abs_company_config
  abs_company_config=$(cd "$(dirname "$company_config")" && echo "$(pwd)/$(basename "$company_config")")
  local updated
  updated=$(jq --arg p "$abs_company_config" '.companyConfig = $p' "$DTF_CONFIG")
  echo "$updated" > "$DTF_CONFIG"
  ok "Saved company config reference: $abs_company_config"

  # Apply company config (de-sanitization)
  apply_company_config "$DTF_WORKFLOW_REPO" "$company_config"

  # Check for extra paths in company config that are missing from dtf-config.json
  local extra_keys
  extra_keys=$(jq -r '.extraPaths // {} | keys[]' "$company_config" 2>/dev/null || true)
  if [[ -n "$extra_keys" ]]; then
    local existing_extras
    existing_extras=$(jq -r '.extraPaths // {} | keys[]' "$DTF_CONFIG" 2>/dev/null || true)
    local missing_keys=()
    while IFS= read -r key; do
      if ! echo "$existing_extras" | grep -qx "$key"; then
        missing_keys+=("$key")
      fi
    done <<< "$extra_keys"

    if [[ ${#missing_keys[@]} -gt 0 ]]; then
      header "Project-Specific Paths"
      info "Company config defines paths not yet in your personal config:"
      echo ""
      local updated_config
      updated_config=$(cat "$DTF_CONFIG")
      for key in "${missing_keys[@]}"; do
        local desc=$(jq -r ".extraPaths[\"$key\"].description // \"$key\"" "$company_config")
        local default_val=$(jq -r ".extraPaths[\"$key\"].default // \"\"" "$company_config")
        local val
        ask "$desc" "$default_val" val
        updated_config=$(echo "$updated_config" | jq --arg k "$key" --arg v "$val" '.extraPaths += {($k): $v}')
      done
      echo "$updated_config" > "$DTF_CONFIG"
      ok "Updated dtf-config.json with new paths"
      # Re-source to pick up new values
      source "$CLAUDE_DIR/scripts/dtf-env.sh"
    fi
  fi

  # Refresh symlinks (file contents changed via sed)
  info "Refreshing symlinks..."
  create_symlinks "$DTF_WORKFLOW_REPO"

  # Re-merge settings (content may have changed)
  merge_settings "$DTF_WORKFLOW_REPO"

  # Re-generate CLAUDE.md (template content may have changed)
  generate_claude_md "$DTF_WORKFLOW_REPO" "$DTF_MONOREPO" "$DTF_TERMINAL"

  header "Company Config Applied"
  info "Run 'dtf doctor' to verify everything looks correct."
}

# ──────────────────────────────────────────────
# dtf configure — set/change role and workflow (works for existing users)
# ──────────────────────────────────────────────

cmd_configure() {
  if [[ ! -f "$DTF_CONFIG" ]]; then
    err "DTF not installed. Run: dtf install <REPO_URL>"
    exit 1
  fi

  header "Configure Your Role & Workflow"

  local current_role
  current_role=$(jq -r '.role // "not set"' "$DTF_CONFIG")
  local current_display
  current_display=$(jq -r '.roleConfig.displayName // "not set"' "$DTF_CONFIG")
  info "Current role: $current_display ($current_role)"
  echo ""

  # 1. Choose role
  local role_display="" role_key=""
  ask_role
  ok "Role: $role_display ($role_key)"

  # 2. Show recommended external skills
  local ext_skills
  ext_skills=$(get_role_external_skills "$role_key")
  if [[ -n "$ext_skills" ]]; then
    echo ""
    info "Recommended external skills for your role:"
    echo -e "$ext_skills" | while IFS= read -r skill; do
      [[ -n "$skill" ]] && info "  → $skill"
    done
  fi

  # 3. Configure workflow steps
  local default_steps
  default_steps=$(get_role_default_steps "$role_key")
  local workflow_steps="$default_steps"

  if [[ "$default_steps" != "[]" ]]; then
    echo ""
    info "Default workflow steps for $role_display:"
    echo "$default_steps" | jq -r '.[] | "  [\(.when)] \(.name) (\(.type))"'
    echo ""

    local customize_steps
    read -rp "  Customize these steps? (y/N): " customize_steps
    if [[ "$customize_steps" =~ ^[yY] ]]; then
      local step_count
      step_count=$(echo "$default_steps" | jq 'length')
      info "Enter step numbers to REMOVE (comma-separated), or press Enter to keep all:"
      for i in $(seq 0 $((step_count - 1))); do
        local step_name step_when step_type
        step_name=$(echo "$default_steps" | jq -r ".[$i].name")
        step_when=$(echo "$default_steps" | jq -r ".[$i].when")
        step_type=$(echo "$default_steps" | jq -r ".[$i].type")
        echo "    $((i+1)). [$step_when] $step_name ($step_type)"
      done
      local remove_indices
      read -rp "  Remove: " remove_indices

      if [[ -n "$remove_indices" ]]; then
        for idx in $(echo "$remove_indices" | tr ',' ' ' | sort -rn); do
          idx=$((idx - 1))
          workflow_steps=$(echo "$workflow_steps" | jq "del(.[$idx])")
        done
      fi

      local add_custom
      read -rp "  Add custom steps? (y/N): " add_custom
      while [[ "$add_custom" =~ ^[yY] ]]; do
        local step_name step_type step_when step_command=""
        ask "Step name" "" step_name
        ask_choice "Step type" step_type "reminder" "automated"
        if [[ "$step_type" == "automated" ]]; then
          ask "Shell command to run" "" step_command
        fi
        ask_choice "When to trigger" step_when "before-commit" "before-push" "before-pr" "after-pr" "on-start"

        if [[ "$step_type" == "automated" ]]; then
          workflow_steps=$(echo "$workflow_steps" | jq \
            --arg n "$step_name" --arg t "$step_type" --arg c "$step_command" --arg w "$step_when" \
            '. + [{"name":$n,"type":$t,"command":$c,"when":$w}]')
        else
          workflow_steps=$(echo "$workflow_steps" | jq \
            --arg n "$step_name" --arg t "$step_type" --arg w "$step_when" \
            '. + [{"name":$n,"type":$t,"when":$w}]')
        fi
        ok "Added: [$step_when] $step_name ($step_type)"
        read -rp "  Add another step? (y/N): " add_custom
      done
    fi
  fi

  # 4. Build role config
  local role_agents
  role_agents=$(get_role_agents "$role_key")
  local role_skills
  role_skills=$(get_role_skills "$role_key")
  local agents_json="[]"
  if [[ -n "$role_agents" ]]; then
    agents_json=$(echo "$role_agents" | tr ' ' '\n' | jq -R . | jq -s .)
  fi
  local skills_json="[]"
  if [[ -n "$role_skills" ]]; then
    skills_json=$(echo "$role_skills" | tr ' ' '\n' | jq -R . | jq -s .)
  fi

  # 5. Update config (preserve existing paths, user, terminal, extraPaths)
  local updated
  updated=$(jq \
    --arg role "$role_key" \
    --arg display "$role_display" \
    --argjson agents "$agents_json" \
    --argjson skills "$skills_json" \
    --argjson steps "$workflow_steps" \
    '.version = 2 |
     .role = $role |
     .roleConfig = {"displayName": $display, "agents": $agents, "skills": $skills} |
     .workflowSteps = $steps' "$DTF_CONFIG")
  echo "$updated" > "$DTF_CONFIG"

  ok "Config updated!"
  echo ""
  info "Your workflow:"
  echo "$workflow_steps" | jq -r '.[] | "  [\(.when)] \(.name) (\(.type))"'
  echo ""
  info "Manage steps anytime with: dtf steps <list|add|remove|reset>"
}

# ──────────────────────────────────────────────
# dtf steps — manage workflow steps
# ──────────────────────────────────────────────

cmd_steps() {
  if [[ ! -f "$DTF_CONFIG" ]]; then
    err "DTF not installed. Run: dtf install <REPO_URL>"
    exit 1
  fi

  local subcmd="${1:-list}"
  shift 2>/dev/null || true

  case "$subcmd" in
    list)
      header "Workflow Steps"
      local steps
      steps=$(jq -r '.workflowSteps // []' "$DTF_CONFIG")
      local count
      count=$(echo "$steps" | jq 'length')

      if [[ "$count" -eq 0 ]]; then
        info "No workflow steps configured."
        info "Add one with: dtf steps add"
        return
      fi

      # Group by 'when'
      for phase in "on-start" "before-commit" "before-push" "before-pr" "after-pr"; do
        local phase_steps
        phase_steps=$(echo "$steps" | jq -r "[.[] | select(.when == \"$phase\")]")
        local phase_count
        phase_count=$(echo "$phase_steps" | jq 'length')
        if [[ "$phase_count" -gt 0 ]]; then
          echo "  [$phase]"
          echo "$phase_steps" | jq -r '.[] | "    \(if .type == "automated" then "⚡" else "📋" end) \(.name)\(if .command then " → " + .command else "" end)"'
        fi
      done
      echo ""
      info "⚡ = automated  📋 = reminder"
      ;;

    add)
      local step_name step_type step_when step_command=""
      ask "Step name" "" step_name
      ask_choice "Step type" step_type "reminder" "automated"
      if [[ "$step_type" == "automated" ]]; then
        ask "Shell command to run" "" step_command
      fi
      ask_choice "When to trigger" step_when "before-commit" "before-push" "before-pr" "after-pr" "on-start"

      local updated
      if [[ "$step_type" == "automated" ]]; then
        updated=$(jq \
          --arg n "$step_name" --arg t "$step_type" --arg c "$step_command" --arg w "$step_when" \
          '.workflowSteps += [{"name":$n,"type":$t,"command":$c,"when":$w}]' "$DTF_CONFIG")
      else
        updated=$(jq \
          --arg n "$step_name" --arg t "$step_type" --arg w "$step_when" \
          '.workflowSteps += [{"name":$n,"type":$t,"when":$w}]' "$DTF_CONFIG")
      fi
      echo "$updated" > "$DTF_CONFIG"
      ok "Added: [$step_when] $step_name ($step_type)"
      ;;

    remove)
      local steps
      steps=$(jq -r '.workflowSteps // []' "$DTF_CONFIG")
      local count
      count=$(echo "$steps" | jq 'length')

      if [[ "$count" -eq 0 ]]; then
        info "No steps to remove."
        return
      fi

      info "Current steps:"
      for i in $(seq 0 $((count - 1))); do
        local name when type
        name=$(echo "$steps" | jq -r ".[$i].name")
        when=$(echo "$steps" | jq -r ".[$i].when")
        type=$(echo "$steps" | jq -r ".[$i].type")
        echo "    $((i+1)). [$when] $name ($type)"
      done

      local idx
      ask "Step number to remove" "" idx
      if [[ -n "$idx" && "$idx" -ge 1 && "$idx" -le "$count" ]]; then
        local removed_name
        removed_name=$(echo "$steps" | jq -r ".[$((idx-1))].name")
        local updated
        updated=$(jq "del(.workflowSteps[$((idx-1))])" "$DTF_CONFIG")
        echo "$updated" > "$DTF_CONFIG"
        ok "Removed: $removed_name"
      else
        err "Invalid step number."
      fi
      ;;

    reset)
      # Reset to role defaults
      source "$CLAUDE_DIR/scripts/dtf-env.sh" 2>/dev/null || true
      local role
      role=$(jq -r '.role // empty' "$DTF_CONFIG")
      if [[ -z "$role" ]]; then
        err "No role configured."
        return
      fi
      local default_steps
      default_steps=$(get_role_default_steps "$role")
      local updated
      updated=$(jq --argjson s "$default_steps" '.workflowSteps = $s' "$DTF_CONFIG")
      echo "$updated" > "$DTF_CONFIG"
      ok "Reset to default steps for role: $role"
      ;;

    *)
      echo "Usage: dtf steps <list|add|remove|reset>"
      ;;
  esac
}

# ──────────────────────────────────────────────
# Main dispatcher
# ──────────────────────────────────────────────

cmd="${1:-help}"
shift 2>/dev/null || true

case "$cmd" in
  install)      cmd_install "$@" ;;
  update)       cmd_update "$@" ;;
  apply-config) cmd_apply_config "$@" ;;
  configure)    cmd_configure "$@" ;;
  doctor)       cmd_doctor "$@" ;;
  contribute)   cmd_contribute "$@" ;;
  steps)        cmd_steps "$@" ;;
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
    echo "  apply-config <path-to-company-config.json> [--update]"
    echo "    Apply company config after install (de-sanitize service names, etc.)"
    echo "    Use --update to also pull latest changes first"
    echo ""
    echo "  configure"
    echo "    Set or change your role and workflow steps (works for existing users)"
    echo ""
    echo "  steps <list|add|remove|reset>"
    echo "    Manage your personal workflow steps"
    echo "    list    — Show current steps grouped by phase"
    echo "    add     — Add a new step (reminder or automated)"
    echo "    remove  — Remove a step by number"
    echo "    reset   — Reset to role defaults"
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
