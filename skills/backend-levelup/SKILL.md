---
name: backend-levelup
description: Personal backend learning path anchored in Repo's own code — four levels (Apprentice request flow, Journeyman data, Senior decisions, Architect systems), a checklist per level with three evidence steps (explain, find in code, done in a PR), a placement test, and questions generated from the area of the ticket being worked on. Tracks progress in a local file. Use when the user says "level up", "placement test", "quiz me", "ställ frågor", "vilken nivå är jag", "nästa steg", asks to be tested on backend, or after a lift-the-gaze session to turn what was decided into a learning item.
user_invocable: true
---

# Backend Level-up

Teaches the backend through Repo's real code and decisions, not generic tutorials. Companion to `lift-the-gaze` (decide this now); this skill is "learn over time". Talk in the user's language. The user is stronger on frontend than backend.

Files:
- `references/levels.md`: the four levels and their checklist items (ids like `L2.3`), each anchored in a file or a decision.
- `references/placement.md`: the placement test, with what a good answer contains.
- Progress: `~/.claude/data/backend-levelup.json` (local, not synced). Create it on first use with `{ "level": null, "items": {}, "history": [] }`.

## Evidence, not confidence

Each checklist item has three steps:

1. **Explain** — the user answers a question about it in their own words, and the answer contains the key points.
2. **Find** — the user points to where it lives in the code (file, class or line). Verify with grep/Read before accepting; a plausible path that doesn't exist does not count.
3. **Done** — a PR where the user used it. Verify the PR with `gh` before accepting.

A level is **reached** when at least 70 % of its items are at step 2 or higher. The current level is the highest reached; the "working level" is the next one.

## Modes

### Placement test (`placement`)
- Ask the questions in `references/placement.md` **one at a time**. Wait for the answer. No hints before the answer.
- After each answer: grade it (full / partial / missing) against the key points, say in two or three lines what was right, what was missing, and where it lives in the code. Then the next question.
- If the user says they forgot or wants it again, repeat the question with the code anchor as a hint, and grade the second attempt as partial at most.
- At the end: give the level per the scoring in `placement.md`, the items that moved to step 1 (Explain), and the two weakest items as the first things to work on. Save to the progress file.

### Area questions (`quiz`, or at the end of a ticket session)
- Find the area: the current worktree's ticket (`.dream-team/jira-ticket.md`), the files in the diff, or what the user names.
- Pick 3 to 5 checklist items from the working level that this area touches. Write each question from **this code** (name the file), not in the abstract. Include at least one "what happens if…" question (concurrency, a redelivered event, a deleted row).
- Grade like the placement test, update the progress file, suggest the next item.

### Progress (`status`)
- Show the level, the working level, items per step, and the next three items to work on. One table, no essay.

### One question per session (`daily`)
- One question from the working level, in the area last touched. Two minutes, no more.

## Rules for questions and grading

- **Anchored:** every question names a real file, endpoint, event or dated decision, and the answer key points to it. Verify anchors still exist before asking (code moves).
- **Repo answers win:** when the textbook answer and Repo's answer differ (for example `ApiResponse<T>` from services, controller → repository allowed, no MediatR), Repo's is correct, and saying the textbook one gets "partial, here is why we differ" with the source from `dotnet-architecture-reference/repo-vs-textbook.md`.
- **Short feedback:** two or three lines per answer. Detail lives in the code anchor.
- **No PII:** people are named by role.
- **Reusing outside tests:** question *topics* from common .NET interview lists and Microsoft Learn knowledge checks may inspire new questions, but write them in our own words and anchor them in Repo. Never copy certification exam questions or "dumps".

## Output

- After grading: `✓ / ½ / ✗  <item id> <one line>` then the 2–3 lines of feedback.
- Never write to Jira, GitHub or Slack from this skill.
