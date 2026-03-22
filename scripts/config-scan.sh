#!/usr/bin/env bash
# config-scan.sh — Scan Claude Code configuration for security issues and optimization opportunities
# Usage: bash ~/.claude/scripts/config-scan.sh [--fix]
# Categories: SECURITY, PERFORMANCE, HYGIENE, RISK

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
FIX_MODE="${1:-}"
ISSUES=0
WARNINGS=0

red()    { printf '\033[0;31m%s\033[0m\n' "$1"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$1"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$1"; }
blue()   { printf '\033[0;34m%s\033[0m\n' "$1"; }

issue()   { ISSUES=$((ISSUES + 1)); red   "[ISSUE]    $1"; }
warning() { WARNINGS=$((WARNINGS + 1)); yellow "[WARNING]  $1"; }
ok()      { green  "[OK]       $1"; }
info()    { blue   "[INFO]     $1"; }

echo "=== Claude Config Scanner ==="
echo "Scanning: $CLAUDE_DIR"
echo ""

# ─── SECURITY ────────────────────────────────────────────────────────

echo "── Security ──"

# Check for secrets in CLAUDE.md files
for f in "$CLAUDE_DIR"/CLAUDE.md "$CLAUDE_DIR"/projects/*/CLAUDE.md; do
  [ ! -f "$f" ] && continue
  if grep -qiE '(api[_-]?key|secret|password|token|credential)\s*[:=]\s*["\x27]?[A-Za-z0-9+/=_-]{20,}' "$f" 2>/dev/null; then
    issue "Possible secret in $f"
  fi
done

# Check for secrets in settings.json env vars
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  SECRETS_IN_ENV=$(jq -r '.env // {} | to_entries[] | select(.value | test("^(sk-|ghp_|ghs_|xoxb-|xoxp-)")) | .key' "$CLAUDE_DIR/settings.json" 2>/dev/null || true)
  if [ -n "$SECRETS_IN_ENV" ]; then
    issue "API keys found in settings.json env: $SECRETS_IN_ENV — use environment variables instead"
  else
    ok "No secrets detected in settings.json env vars"
  fi
fi

# Check for dangerouslySkipPermissions
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  if jq -e '.skipDangerousModePermissionPrompt == true' "$CLAUDE_DIR/settings.json" &>/dev/null; then
    warning "skipDangerousModePermissionPrompt is enabled — all tools run without confirmation"
  fi
fi

# Check hook scripts for eval usage (only scripts referenced by hooks)
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  jq -r '.. | strings | select(startswith("~/")) | select(endswith(".sh"))' "$CLAUDE_DIR/settings.json" 2>/dev/null | sort -u | while read -r script; do
    expanded="${script/#\~/$HOME}"
    [ ! -f "$expanded" ] && continue
    if grep -qE 'eval\s' "$expanded" 2>/dev/null; then
      warning "eval found in $(basename "$expanded") — potential command injection in hook script"
    fi
  done
fi
ok "Hook scripts scanned for injection patterns"

# Scan installed skills for suspicious patterns
SKILL_ISSUES=0
for skill_dir in "$CLAUDE_DIR"/skills/*/; do
  [ ! -d "$skill_dir" ] && continue
  skill_name=$(basename "$skill_dir")
  # Check for shell execution in SKILL.md that could be dangerous
  for f in "$skill_dir"*.md "$skill_dir"**/*.md; do
    [ ! -f "$f" ] && continue
    # Look for dangerous patterns outside of code blocks (``` fenced blocks are examples)
    # Extract non-fenced content and check for: curl piped to sh, eval, rm -rf /, chmod 777
    NON_FENCED=$(awk '/^```/{skip=!skip; next} !skip{print}' "$f" 2>/dev/null)
    if echo "$NON_FENCED" | grep -qiE '(curl|wget)\s+[^#]*\|.*sh|eval\s|rm\s+-rf\s+/|chmod\s+777' 2>/dev/null; then
      warning "Suspicious pattern in skill $skill_name/$(basename "$f") — review manually"
      SKILL_ISSUES=$((SKILL_ISSUES + 1))
    fi
    # Look for hardcoded API keys/tokens
    if grep -qiE '(api[_-]?key|secret|token)\s*[:=]\s*["\x27][A-Za-z0-9+/=_-]{20,}' "$f" 2>/dev/null; then
      issue "Possible secret in skill $skill_name/$(basename "$f")"
    fi
  done
done
if [ "$SKILL_ISSUES" -eq 0 ]; then
  ok "Skills scanned: no suspicious patterns in $(ls -d "$CLAUDE_DIR"/skills/*/ 2>/dev/null | wc -l | tr -d ' ') skills"
fi

# Scan agent definitions for overly broad tool access
AGENT_ISSUES=0
for agent_file in "$CLAUDE_DIR"/agents/**/*.md "$CLAUDE_DIR"/agents/*.md; do
  [ ! -f "$agent_file" ] && continue
  agent_name=$(basename "$agent_file" .md)
  # Check for dangerous tool combinations
  if grep -qiE 'tools:.*Bash' "$agent_file" 2>/dev/null; then
    if grep -qiE 'model:.*opus' "$agent_file" 2>/dev/null; then
      : # Opus with Bash is fine (trusted model)
    else
      # Sonnet with Bash — note but don't flag
      : # info "Agent $agent_name: Sonnet model with Bash access"
    fi
  fi
done

# Check company-config.json for issues
COMPANY_CONFIG="$CLAUDE_DIR/company-config.json"
if [ -f "$COMPANY_CONFIG" ]; then
  # Check for real credentials
  if grep -qiE '(password|secret|api.?key)\s*[:=]\s*"[^"]{8,}"' "$COMPANY_CONFIG" 2>/dev/null; then
    issue "Possible credentials in company-config.json"
  else
    ok "company-config.json: no credentials detected"
  fi
  # Check it's valid JSON
  if ! jq empty "$COMPANY_CONFIG" 2>/dev/null; then
    warning "company-config.json is not valid JSON"
  fi
fi

# Check permissions section
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  # Count allowed permissions
  ALLOW_COUNT=$(jq '[.permissions // {} | to_entries[] | select(.value == "allow")] | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)
  DENY_COUNT=$(jq '[.. | objects | select(.deny) | .deny[]] | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)
  info "Permissions: $ALLOW_COUNT allowed, $DENY_COUNT denied"

  # Check for wildcard allows
  if jq -e '.permissions | to_entries[] | select(.key == "*" and .value == "allow")' "$CLAUDE_DIR/settings.json" &>/dev/null 2>&1; then
    warning "Wildcard permission allow (*) — all tools run without confirmation"
  fi
fi

# Check MCP server count
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  MCP_COUNT=$(jq '.mcpServers // {} | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)
  if [ "$MCP_COUNT" -gt 10 ]; then
    warning "MCP servers: $MCP_COUNT enabled (recommended: <10 to preserve context window)"
  elif [ "$MCP_COUNT" -gt 0 ]; then
    info "MCP servers: $MCP_COUNT enabled"
  else
    ok "No MCP servers (minimal attack surface)"
  fi
fi

echo ""

# ─── PERFORMANCE ─────────────────────────────────────────────────────

echo "── Performance ──"

if [ -f "$CLAUDE_DIR/settings.json" ]; then
  # Check MAX_THINKING_TOKENS
  THINKING=$(jq -r '.env.MAX_THINKING_TOKENS // "not set"' "$CLAUDE_DIR/settings.json" 2>/dev/null)
  if [ "$THINKING" = "not set" ]; then
    warning "MAX_THINKING_TOKENS not set — hidden thinking costs may be high. Consider: 10000-16000"
  else
    ok "MAX_THINKING_TOKENS: $THINKING"
  fi

  # Check autocompact
  AUTOCOMPACT=$(jq -r '.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE // "not set"' "$CLAUDE_DIR/settings.json" 2>/dev/null)
  if [ "$AUTOCOMPACT" = "not set" ]; then
    info "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE not set — using default. Consider 50 for long sessions."
  else
    ok "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: $AUTOCOMPACT%"
  fi

  # Check effort level
  EFFORT=$(jq -r '.effortLevel // "not set"' "$CLAUDE_DIR/settings.json" 2>/dev/null)
  info "Effort level: $EFFORT"
fi

# Check CLAUDE.md size
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  LINES=$(wc -l < "$CLAUDE_DIR/CLAUDE.md")
  if [ "$LINES" -gt 300 ]; then
    warning "CLAUDE.md is $LINES lines — consider moving heavy docs to skills (on-demand loading)"
  else
    ok "CLAUDE.md size: $LINES lines (healthy)"
  fi
fi

# Check memory index size
for mf in "$CLAUDE_DIR"/projects/*/memory/MEMORY.md; do
  [ ! -f "$mf" ] && continue
  MLINES=$(wc -l < "$mf")
  if [ "$MLINES" -gt 180 ]; then
    warning "Memory index is $MLINES lines (truncates at 200)"
  else
    ok "Memory index: $MLINES/200 lines"
  fi
done

echo ""

# ─── HYGIENE ─────────────────────────────────────────────────────────

echo "── Hygiene ──"

# Check for stale CHECKPOINT.md files
CHECKPOINTS=$(find "$HOME/Documents" -maxdepth 2 -name "CHECKPOINT.md" -mtime +1 2>/dev/null | wc -l | tr -d ' ')
if [ "$CHECKPOINTS" -gt 0 ]; then
  info "$CHECKPOINTS stale CHECKPOINT.md files — safe to delete"
fi

# Check tool usage log size
if [ -f "$CLAUDE_DIR/logs/tool-usage.csv" ]; then
  LOG_LINES=$(wc -l < "$CLAUDE_DIR/logs/tool-usage.csv")
  LOG_SIZE=$(du -h "$CLAUDE_DIR/logs/tool-usage.csv" | cut -f1)
  if [ "$LOG_LINES" -gt 50000 ]; then
    warning "Tool usage log: $LOG_LINES lines ($LOG_SIZE) — consider archiving"
  else
    ok "Tool usage log: $LOG_LINES lines ($LOG_SIZE)"
  fi
fi

# Check hook scripts exist and are executable
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  jq -r '.. | strings | select(startswith("~/")) | select(endswith(".sh"))' "$CLAUDE_DIR/settings.json" 2>/dev/null | sort -u | while read -r script; do
    expanded="${script/#\~/$HOME}"
    if [ ! -f "$expanded" ]; then
      issue "Hook script missing: $script"
    elif [ ! -x "$expanded" ]; then
      warning "Hook script not executable: $script"
      if [ "$FIX_MODE" = "--fix" ]; then
        chmod +x "$expanded"
        ok "Fixed: chmod +x $expanded"
      fi
    fi
  done
fi

echo ""

# ─── RISK ────────────────────────────────────────────────────────────

echo "── Risk ──"

# Check for async hooks without timeout
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  ASYNC_NO_TIMEOUT=$(jq '[.. | objects | select(.async == true and (.timeout == null or .timeout == 0))] | length' "$CLAUDE_DIR/settings.json" 2>/dev/null || echo 0)
  if [ "$ASYNC_NO_TIMEOUT" -gt 0 ]; then
    warning "$ASYNC_NO_TIMEOUT async hooks without explicit timeout"
  else
    ok "All async hooks have timeouts"
  fi
fi

echo ""

# ─── SUMMARY ─────────────────────────────────────────────────────────

echo "════════════════════════════════"
if [ "$ISSUES" -gt 3 ]; then GRADE="F"
elif [ "$ISSUES" -gt 1 ]; then GRADE="D"
elif [ "$ISSUES" -gt 0 ]; then GRADE="C"
elif [ "$WARNINGS" -gt 5 ]; then GRADE="B"
else GRADE="A"
fi

echo "Grade: $GRADE  |  Issues: $ISSUES  |  Warnings: $WARNINGS"
if [ "$GRADE" = "A" ]; then
  green "Config looks healthy!"
elif [ "$GRADE" = "B" ]; then
  yellow "Minor optimizations available."
else
  red "Issues found — review above."
fi

exit $([ "$ISSUES" -gt 0 ] && echo 2 || echo 0)
