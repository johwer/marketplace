#!/bin/bash
# worktree-port-overlay.sh — Apply worktree port config from PLRS-1847 branch
#
# Copies the worktree port infrastructure files from the PLRS-1847/worktree-port-config
# branch into a worktree WITHOUT committing them. Uses git assume-unchanged +
# .gitignore to keep them invisible to git status/diff/PRs.
#
# Usage:
#   bash ~/.claude/scripts/worktree-port-overlay.sh <TICKET_ID>
#
# What it does:
#   1. Copies scripts (allocate-ports.sh, worktree-service.sh, generate-api.sh)
#   2. Copies docker-compose.worktree.yml
#   3. Overlays vite.config.mts with the env-var-aware version
#   4. Appends overlay patterns to .gitignore (for untracked files)
#   5. Marks modified tracked files as assume-unchanged (for tracked files)
#   6. Runs allocate-ports.sh to generate unique ports
#
# After PLRS-1847 merges to main, this script is no longer needed — remove it.

set -euo pipefail

TICKET_ID="${1:?Usage: $0 <TICKET_ID>}"
WORKTREE_DIR="$HOME/Documents/$TICKET_ID"
MEDHELP_ROOT="${MEDHELP_ROOT:-$HOME/Documents/MedHelp}"
SOURCE_BRANCH="origin/PLRS-1847/worktree-port-config"

if [ ! -d "$WORKTREE_DIR" ]; then
    echo "ERROR: Worktree $WORKTREE_DIR does not exist" >&2
    exit 1
fi

echo "Applying worktree port overlay for $TICKET_ID..."

# Ensure we have the branch ref
cd "$MEDHELP_ROOT"
git fetch origin PLRS-1847/worktree-port-config 2>/dev/null || true

# Files to overlay from the branch
OVERLAY_FILES=(
    "scripts/allocate-ports.sh"
    "scripts/worktree-service.sh"
    "scripts/generate-api.sh"
    "docker-compose.worktree.yml"
    "apps/web/vite.config.mts"
)

# Copy each file from the branch into the worktree
cd "$WORKTREE_DIR"
for file in "${OVERLAY_FILES[@]}"; do
    dir=$(dirname "$file")
    mkdir -p "$dir"
    git -C "$MEDHELP_ROOT" show "$SOURCE_BRANCH:$file" > "$file" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "  Overlaid: $file"
    else
        echo "  WARNING: Could not extract $file from $SOURCE_BRANCH" >&2
    fi
done

# Make scripts executable
chmod +x scripts/allocate-ports.sh 2>/dev/null || true
chmod +x scripts/worktree-service.sh 2>/dev/null || true
chmod +x scripts/generate-api.sh 2>/dev/null || true

# --- Git invisibility: two-pronged approach ---

# 1. Mark tracked files that were modified as assume-unchanged
#    (vite.config.mts is tracked on main — overlaying it shows as modified)
git update-index --assume-unchanged apps/web/vite.config.mts 2>/dev/null || true

# 2. Append untracked overlay file patterns to .gitignore
#    Check if we already added the block (idempotent)
if ! grep -q "Worktree port overlay" .gitignore 2>/dev/null; then
    cat >> .gitignore << 'GITIGNORE'

# Worktree port overlay (temporary until PLRS-1847 merges)
docker-compose.worktree.yml
scripts/allocate-ports.sh
scripts/worktree-service.sh
scripts/generate-api.sh
apps/web/vite.config.worktree.mts
apps/web/src/api/.openapi-config-*-worktree.ts
GITIGNORE
    echo "  Added overlay patterns to .gitignore"
fi

# 3. Mark .gitignore itself as assume-unchanged so the append doesn't show
git update-index --assume-unchanged .gitignore 2>/dev/null || true

echo "  Tracked files marked assume-unchanged, untracked files in .gitignore"

# Run allocate-ports.sh to generate unique ports for this worktree
bash scripts/allocate-ports.sh "$TICKET_ID"

echo ""
echo "Worktree port overlay applied for $TICKET_ID."
echo "Files are invisible to git — they won't appear in PRs."
echo ""
echo "After PLRS-1847/worktree-port-config merges to main, run:"
echo "  rm ~/.claude/scripts/worktree-port-overlay.sh"
