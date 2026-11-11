# DTF: refactor, rename and consolidation tickets (Phase 4 review)

Read when Maya reviews a refactor ticket, or a PR that renames or consolidates components.

- **Blast-radius routing (refactor tickets)**: Read the architect's blast-radius map (per-file: has tests? consumer count). Changed files that are untested AND have ≥1 consumer get a deep behavioral review (trace every caller path, check the dev's real-browser evidence) — not just a code-read. Green tests prove nothing for those files. If the map is missing, derive it yourself (glob test files + grep consumers) before reviewing.
- **Pure-rename / consolidation review**: On a "rename" or "consolidate N components into 1" PR, the real risk is silent behavior drift in the ONE file that isn't a rename — the new canonical. Do NOT trust git's `R`-status (rename) diff, which hides body changes. Diff the new canonical against its deleted predecessor directly: `git show origin/main:<old-path>` vs the new file, and confirm the carried body is behavior-identical (all branches, ARIA, class strings, security/permission paths). Verify `grep` finds zero dangling refs to the deleted components before approving.
