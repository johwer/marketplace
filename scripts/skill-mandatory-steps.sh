#!/bin/bash
# PreToolUse hook — fires before any Skill tool invocation.
# Outputs mandatory checklists for specific skills so Claude has them front of mind.
#
# Receives JSON on stdin: { "skill": "...", "args": "..." }
# Exit 0 = allow (with optional stdout reminder)
# Exit 2 = block — forces re-invocation with explicit acknowledgment

set -euo pipefail

INPUT=$(cat)
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
ARGS=$(echo "$INPUT" | jq -r '.tool_input.args // empty' 2>/dev/null)

case "$SKILL" in
  retro-proposals)
    # If args contain --ack, the acknowledgment has been given — allow through
    if echo "$ARGS" | grep -q -- '--ack'; then
      exit 0
    fi

    cat >&2 <<'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SKILL GATE: retro-proposals — BLOCKED

This skill has mandatory Ticket+PR steps that have been skipped in past runs.

Before this skill can run, you MUST re-invoke it with args: --ack

By passing --ack you commit to executing ALL 7 steps for every Ticket+PR item:
  1. Create Jira ticket   → acli jira workitem create --project PLRS --type Uppgift
  2. Create branch        → git checkout -b retro-learnings-<date>
  3. Edit destination files on the branch
  4. Commit with Jira ref → git commit -m "PROJ-XXXX: ..."
  5. Create draft PR      → gh pr create --draft
  6. Mark items ~~done~~  → in dream-team-learnings.md with ticket ID and PR number
  7. Report ticket ID and PR URL to the user

These steps are NON-NEGOTIABLE. No step may be skipped even if it "feels like
overhead" or the change is "just documentation."

Re-invoke the skill now with args: --ack
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    exit 2
    ;;

  my-dream-team)
    # In full Dream Team mode, named agents (ingrid, elsa, amara, kenji…) are
    # covered by TeammateIdle and TaskCompleted hooks for Phase 4.75 and 6.75.
    # In --lite mode there are NO named agents, so those hooks never fire.
    # We must block here and require --ack so the mandatory phases are acknowledged.
    if echo "$ARGS" | grep -q -- '--lite'; then
      if echo "$ARGS" | grep -q -- '--ack'; then
        exit 0
      fi

      cat >&2 <<'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SKILL GATE: my-dream-team --lite — BLOCKED

In lite mode there are no named agents, so TeammateIdle and TaskCompleted
hooks that enforce Phase 4.75 and Phase 6.75 NEVER FIRE.
You are the sole executor. You must self-enforce these gates.

Before this skill can run, re-invoke it with args: --lite --ack

By passing --ack you commit to ALL mandatory phases — same as full mode:

Phase 4.75 — Visual verification (required if ticket has UI changes):
  • Write Playwright e2e tests in apps/web/tests/e2e/<feature-area>/
  • Tests must take screenshots → <component-dir>/__screenshots__/<Name>-<state>.png
  • Run: npx playwright test
  • Do NOT push without screenshots committed
  • If no UI changes: output explicit statement "No UI changes — 4.75 skipped"

Phase 6.75 — Retrospective (required every session):
  • Write journal entry to .dream-team/journal/lead.md
  • Append learnings to dream-team-learnings.md
  • Update dream-team-history.json with session metrics
  • This phase is NOT optional even if "nothing went wrong"

Phase 7 — Completion Gate (ALL items in Section 9 of dev-workflow-checklist.md):
  • PR comments resolved
  • Screenshots committed (if UI changes)
  • Retro done
  • CI green
  • PR description complete
  • Jira completion comment posted
  • Ticket transitioned to Klart

These are HARD GATES. Lite mode does not reduce scope — only team size.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 2
    fi

    # Full Dream Team mode — hooks cover named agents. Print reminder only.
    cat >&2 <<'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SKILL GATE: my-dream-team — HARD GATES (DO NOT SKIP)

Phase 4.75 — Visual verification (required if UI changes):
  • Write Playwright e2e tests in apps/web/tests/e2e/<feature-area>/
  • Tests must take screenshots → <component-dir>/__screenshots__/<Name>-<state>.png
  • Run: npx playwright test
  • Do NOT push without screenshots committed

Phase 6.75 — Retrospective (required every session):
  • Write journal entries to .dream-team/journal/<agent>.md
  • Append learnings to dream-team-learnings.md
  • Update dream-team-history.json with session metrics

Phase 7 — Completion Gate (ALL items in Section 9 of dev-workflow-checklist.md):
  • PR comments resolved
  • Screenshots committed (if UI changes)
  • Retro done
  • CI green
  • PR description complete
  • Jira completion comment posted
  • Ticket transitioned to Klart

These are HARD GATES. Skipping any of them is not allowed.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    ;;
esac

exit 0
