# Sync Config — Push Claude Configuration to GitHub

Sync Claude configuration files to the repos `scripts/sync-config.sh` lists in its header (a private marketplace, a sanitized public marketplace, and the public `dream-team-flow` repo) and push to GitHub.

## Workflow

Run the sync script:

```bash
bash ~/.claude/scripts/sync-config.sh
```

The script will:
1. Compare checksums of all tracked files between `~/.claude/` and the repo
2. Show which files are new or changed
3. Copy updated files to the repo
4. Commit with a descriptive message listing what changed
5. Push to GitHub (switching to the `your-username` account if needed, then switching back)

If the script reports no changes, tell the user everything is already in sync.

## Adding New Files to Track

If the user wants to track additional files, edit the `PLUGIN_FILES` or `PLUGIN_DIRS` arrays in `~/.claude/scripts/sync-config.sh`.
