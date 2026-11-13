# DTF: feature-flag gating with PostHog (Phase 4.95)

Read when Amara set `needs_feature_flag: true` in Phase 1.

**Applies in BOTH lite and team flows** — in lite mode the team lead does all of it; in team mode the frontend dev wires the guards and the team lead creates the flag.

Unfinished UI is gated on the frontend (repo `AGENTS.md` "Slice"): read the flag and skip the data fetch / hide the render when it's off. ServiceD.API also registers a server-side PostHog flag service (`IFeatureFlagService`); use it only when the ticket needs backend behaviour behind the flag.

1. **Wire the frontend guard** (frontend dev): add a named hook next to the others in `apps/web/src/utils/posthogFeatureFlags.ts` (`useFeatureFlagEnabled("<flag-key>")` from `@posthog/react`). Prefer gating at the data-fetch boundary — pass `skipToken` to the RTK Query when the flag is off, which also hides the render (no data → nothing to show).

2. **Create the flag in PostHog** (team lead) using the DTF handler — idempotent, applies the team-standard config (Boolean, accept+staging hosts OR'd, 100%, active), and reuses the API key from the keychain (no re-paste):
   ```bash
   # Pass the ticket + a short slug; the script derives the standard key shape
   # <ticket-lowercased>-<kebab-slug>, guaranteeing the ticket number is in the key.
   ~/.claude/scripts/posthog-create-flag.sh \
     --ticket "<TICKET-ID>" \
     --key "<short feature slug>"      # e.g. --ticket PROJ-2831 --key "Legacy user redirect"
                                       #   -> proj-2831-legacy-user-redirect
   ```
   - **Where the API key comes from** (the script resolves it automatically, in this order): (1) `$POSTHOG_PERSONAL_API_KEY` env var, (2) the **macOS keychain** — service `posthog-personal-api-key` (read it manually with `security find-generic-password -s posthog-personal-api-key -w`), (3) interactive prompt. It prints which source it used. If it's not stored yet, run `~/.claude/scripts/posthog-setup-key.sh` once to capture a scoped key into the keychain (+ project id into `dtf-config.json`). The non-secret config (projectId/apiHost) lives in `dtf-config.json` under `posthog`.
   - Use this **exact derived key** in the code's `useFeatureFlagEnabled("<derived-key>")` — they must match or the feature silently stays hidden.
   - The script writes the release condition on `$initial_host` (never hand-edit a flag back to `$host`) and exits non-zero if the flag is not on for every host. A non-zero exit is a failed step — do not move on and do not report the flag as created.
   - **A flag read before login cannot use a host condition at all** (`$initial_host` only exists after `identify`). If the guarded code runs pre-login, raise it with the user — it needs `posthog.setPersonPropertiesForFlags({ $host: window.location.host })` after `posthog.init` in `apps/web/src/index.tsx` (as SignedIn does), plus a `$host` condition.

3. **Confirm with the user** which environments/rollout they want (the standard is accept + staging at 100%, prod off). Adjust `--hosts` / `--rollout` if they want something different. Hosts: **`app-accept.repo.se` = Repo accept**, `polaris-accept.repo.se` = TT accept, `leo-stg.retailer-b.com` = TT staging. The script's default is the two TT hosts — pass `--hosts app-accept.repo.se` for a Repo-only rollout. Updating an existing flag keeps its description unless `--description` is passed.

4. The feature ships **flag-off in prod by default** — safe. The user enables/rolls out via PostHog after merge.

5. **Verifying flag-gated UI locally:** read memory `reference_nova_posthog_feature_flags` BEFORE the
   first browser run. Flags are host-targeted, so localhost renders without the feature even with a
   real UA, and headless Chromium gets no flags at all. Rewrite PostHog's `/flags` response with a
   route in the first script instead of discovering this on the third run.
