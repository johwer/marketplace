# DTF: investigation ticket
Read when the ticket is an investigation (`ticketType: investigation`, no code).

Investigation tickets take a short path; everything that assumes a diff is skipped and SAID so:
- Jira → Pågående at start.
- Phase 1 with the Investigation rules (Phase 1).
- Findings written to `~/Downloads/<TICKET_ID>/findings.md` with file:line and trunk commits.
- Proposed follow-up tickets shown to the user, and every Jira write (create, comment, transition) only after approval.
- → Klart; Phase 6.75 learnings only.
- No draft PR, no 4.75/5/5.5, and Phase 6.9 prints `SKIPPED — investigation, no diff` for each code marker.
