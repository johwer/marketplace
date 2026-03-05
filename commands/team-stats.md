# Team Stats — Dream Team Leaderboard & History

Show cumulative statistics, achievements, and shoutouts for the Dream Team agents.

## Workflow

1. **Read the history file** — look for `dream-team-history.json` in your project memory directory (`~/.claude/projects/*/memory/`). Search for the directory matching your current project. If it doesn't exist, tell the user no sessions have been recorded yet.

2. **Calculate and display stats** in this format:

```
## Dream Team Leaderboard

### Agent Stats
| Agent  | Role             | Sessions | Achievements | Shoutouts |
|--------|------------------|----------|--------------|-----------|
| Amara  | Architect        | 0        | —            | 0         |
| Kenji  | Backend          | 0        | —            | 0         |
| Ravi   | Backend (pool)   | 0        | —            | 0         |
| Ingrid | Frontend         | 0        | —            | 0         |
| Elsa   | Frontend (pool)  | 0        | —            | 0         |
| Diego  | Infra            | 0        | —            | 0         |
| Maya   | PR Review        | 0        | —            | 0         |
| Suki   | Tester           | 0        | —            | 0         |
| Tane   | Summary          | 0        | —            | 0         |

### Achievement Legend
- 🎯 Bullseye — Architecture plan needed 0 changes
- 🧹 Clean Code — 0 MUST FIX items in PR review
- ⚡ Speed — First to complete tasks
- 🤝 Collaborator — Most shoutouts in a session
- 🛡️ Guardian — Found security/critical issue
- 📐 Precision — Infra worked on first try
- 🏗️ Veteran — 10+ sessions
- 🌟 MVP — 3+ shoutouts in one session

### Recent Sessions
[Show the last 5 sessions with date, ticket ID, type, and agents involved]

### Top Shoutout Reasons
[Show the 5 most common shoutout themes across all sessions]
```

3. **If the user asks for a specific agent**, show detailed stats for that agent including all their shoutout reasons and session-by-session performance.
