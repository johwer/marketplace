# Marketplace

Plugin marketplace for Claude Code workflows and tools. Any repo can use any command, agent, or script from this marketplace.

## Install

```bash
/plugin marketplace add johwer/marketplace
/plugin install claude-toolkit@marketplace
```

## What's Included

| Type | Contents |
|------|----------|
| **Commands** | Dream Team orchestration, PR review, ticket scout, retro analysis, workspace management |
| **Agents** | Architect (Opus), PR reviewer (Opus), backend/frontend/data devs (Sonnet) |
| **Scripts** | Quality gates, Chrome queue, workspace launch/cleanup, CI polling |
| **Docs** | Dev workflow checklist, learning system, integration guides |

## For Development Repos

This marketplace is repo-agnostic. Point any development repo at it:

```json
// your-repo/.claude/settings.json
{
  "extraKnownMarketplaces": {
    "marketplace": {
      "source": {
        "source": "github",
        "repo": "johwer/marketplace"
      }
    }
  }
}
```

## Companion Repos

- [dream-team-flow](https://github.com/johwer/dream-team-flow) — DTF framework documentation, improvement plan, and `dtf` CLI for company-specific setup
