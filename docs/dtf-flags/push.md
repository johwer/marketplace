# DTF: stacked branches and explicit-URL push/fetch (Phase 5 push)

Read when the branch is stacked on another PR's branch, or you push or fetch over an explicit URL instead of `origin`.

- **Stacked branch:** re-fetch the base and check ancestry (`git merge-base --is-ancestor origin/<base> HEAD`) before EVERY push — the base can be force-pushed mid-session. `quality-gate.sh` measures freshness against the PR's base and warns that CI will not build a non-main-based PR, instead of waiting.
- After pushing to an explicit URL, `git update-ref refs/remotes/origin/<branch> HEAD` once `git ls-remote` confirms, so ahead/behind stays truthful.
- Fetching over an explicit HTTPS URL needs the leading `+` (`git fetch <url> +main:refs/remotes/origin/main`); without it a non-fast-forward update is silently refused and the tracking ref goes stale after a force-push.
