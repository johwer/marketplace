# DTF: --local
Read when the arguments contain `--local`.

- **Skip Phase 1.5** (no draft PR creation)
- **Skip Phase 5** (no commit, push, or PR ready)
- **Skip Phase 6** (no user review loop — stop after review/testing)
- Still run: architecture (Phase 1), implementation (Phase 2), coordination (Phase 3), code review (Phase 4), testing (Phase 4.5 if flagged), de-sloppify (Phase 4.9)
- After Maya's review (and Suki's testing if applicable) is clean and de-sloppify pass is done, **stop and tell the user** that changes are ready for local review with `git diff`
- Do NOT run retrospective or cleanup phases
