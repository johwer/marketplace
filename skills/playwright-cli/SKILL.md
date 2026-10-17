---
name: playwright-cli
description: Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when the user needs to navigate websites, interact with web pages, fill forms, take screenshots, test web applications, or extract information from web pages.
allowed-tools: Bash(playwright-cli:*)
---

# Browser Automation with playwright-cli

## Quick start

```bash
# open new browser
playwright-cli open
# navigate to a page
playwright-cli goto https://playwright.dev
# interact with the page using refs from the snapshot
playwright-cli click e15
playwright-cli type "page.click"
playwright-cli press Enter
# take a screenshot (rarely used, as snapshot is more common)
playwright-cli screenshot
# close the browser
playwright-cli close
```

## Commands

### Core

```bash
playwright-cli open
# open and navigate right away
playwright-cli open https://example.com/
playwright-cli goto https://playwright.dev
playwright-cli type "search query"
playwright-cli click e3
playwright-cli dblclick e7
playwright-cli fill e5 "user@example.com"
playwright-cli drag e2 e8
playwright-cli hover e4
playwright-cli select e9 "option-value"
playwright-cli upload ./document.pdf
playwright-cli check e12
playwright-cli uncheck e12
playwright-cli snapshot
playwright-cli snapshot --filename=after-click.yaml
playwright-cli eval "document.title"
playwright-cli eval "el => el.textContent" e5
playwright-cli dialog-accept
playwright-cli dialog-accept "confirmation text"
playwright-cli dialog-dismiss
playwright-cli resize 1920 1080
playwright-cli close
```

### Navigation

```bash
playwright-cli go-back
playwright-cli go-forward
playwright-cli reload
```

### Keyboard

```bash
playwright-cli press Enter
playwright-cli press ArrowDown
playwright-cli keydown Shift
playwright-cli keyup Shift
```

### Mouse

```bash
playwright-cli mousemove 150 300
playwright-cli mousedown
playwright-cli mousedown right
playwright-cli mouseup
playwright-cli mouseup right
playwright-cli mousewheel 0 100
```

### Save as

```bash
playwright-cli screenshot
playwright-cli screenshot e5
playwright-cli screenshot --filename=page.png
playwright-cli pdf --filename=page.pdf
```

### Tabs

```bash
playwright-cli tab-list
playwright-cli tab-new
playwright-cli tab-new https://example.com/page
playwright-cli tab-close
playwright-cli tab-close 2
playwright-cli tab-select 0
```

### Storage

```bash
playwright-cli state-save
playwright-cli state-save auth.json
playwright-cli state-load auth.json

# Cookies
playwright-cli cookie-list
playwright-cli cookie-list --domain=example.com
playwright-cli cookie-get session_id
playwright-cli cookie-set session_id abc123
playwright-cli cookie-set session_id abc123 --domain=example.com --httpOnly --secure
playwright-cli cookie-delete session_id
playwright-cli cookie-clear

# LocalStorage
playwright-cli localstorage-list
playwright-cli localstorage-get theme
playwright-cli localstorage-set theme dark
playwright-cli localstorage-delete theme
playwright-cli localstorage-clear

# SessionStorage
playwright-cli sessionstorage-list
playwright-cli sessionstorage-get step
playwright-cli sessionstorage-set step 3
playwright-cli sessionstorage-delete step
playwright-cli sessionstorage-clear
```

### Network

```bash
playwright-cli route "**/*.jpg" --status=404
playwright-cli route "https://api.example.com/**" --body='{"mock": true}'
playwright-cli route-list
playwright-cli unroute "**/*.jpg"
playwright-cli unroute
```

### DevTools

```bash
playwright-cli console
playwright-cli console warning
playwright-cli network
playwright-cli run-code "async page => await page.context().grantPermissions(['geolocation'])"
playwright-cli tracing-start
playwright-cli tracing-stop
playwright-cli video-start
playwright-cli video-stop video.webm
```

## Open parameters
```bash
# Use specific browser when creating session
playwright-cli open --browser=chrome
playwright-cli open --browser=firefox
playwright-cli open --browser=webkit
playwright-cli open --browser=msedge
# Connect to browser via extension
playwright-cli open --extension

# Use persistent profile (by default profile is in-memory)
playwright-cli open --persistent
# Use persistent profile with custom directory
playwright-cli open --profile=/path/to/profile

# Start with config file
playwright-cli open --config=my-config.json

# Close the browser
playwright-cli close
# Delete user data for the default session
playwright-cli delete-data
```

## Snapshots

After each command, playwright-cli provides a snapshot of the current browser state.

```bash
> playwright-cli goto https://example.com
### Page
- Page URL: https://example.com/
- Page Title: Example Domain
### Snapshot
[Snapshot](.playwright-cli/page-2026-02-14T19-22-42-679Z.yml)
```

You can also take a snapshot on demand using `playwright-cli snapshot` command.

If `--filename` is not provided, a new snapshot file is created with a timestamp. Default to automatic file naming, use `--filename=` when artifact is a part of the workflow result.

## Browser Sessions

```bash
# create new browser session named "mysession" with persistent profile
playwright-cli -s=mysession open example.com --persistent
# same with manually specified profile directory (use when requested explicitly)
playwright-cli -s=mysession open example.com --profile=/path/to/profile
playwright-cli -s=mysession click e6
playwright-cli -s=mysession close  # stop a named browser
playwright-cli -s=mysession delete-data  # delete user data for persistent session

playwright-cli list
# Close all browsers
playwright-cli close-all
# Forcefully kill all browser processes
playwright-cli kill-all
```

## Local installation

The npm package is **`@playwright/cli`**, not `playwright-cli`, so `npx playwright-cli` fails with "could not determine executable". If `playwright-cli` is not on PATH (a global npm install belongs to one nvm Node version, so switching Node loses it), install it or run it through npx with the package name:

```bash
npm i -g @playwright/cli@0.1.22
npx @playwright/cli open https://example.com
npx @playwright/cli click e1
```

## Example: Form submission

```bash
playwright-cli open https://example.com/form
playwright-cli snapshot

playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password123"
playwright-cli click e3
playwright-cli snapshot
playwright-cli close
```

## Example: Multi-tab workflow

```bash
playwright-cli open https://example.com
playwright-cli tab-new https://example.com/other
playwright-cli tab-list
playwright-cli tab-select 0
playwright-cli snapshot
playwright-cli close
```

## Example: Debugging with DevTools

```bash
playwright-cli open https://example.com
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli console
playwright-cli network
playwright-cli close
```

```bash
playwright-cli open https://example.com
playwright-cli tracing-start
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli tracing-stop
playwright-cli close
```

## Specific tasks

* **Request mocking** [references/request-mocking.md](references/request-mocking.md)
* **Running Playwright code** [references/running-code.md](references/running-code.md)
* **Browser session management** [references/session-management.md](references/session-management.md)
* **Storage state (cookies, localStorage)** [references/storage-state.md](references/storage-state.md)
* **Test generation** [references/test-generation.md](references/test-generation.md)
* **Tracing** [references/tracing.md](references/tracing.md)
* **Video recording** [references/video-recording.md](references/video-recording.md)

## HARD RULE — mask national IDs before EVERY screenshot (Repo)

Every capture that can leave this machine (PR body, Jira, Slack) must be masked first. A shot with an
unmasked personnummer reached a PR on 2026-10-15 because masking was a habit, not a step.

```bash
bash ~/.claude/scripts/pw-mask-pii.sh <session> && \
  playwright-cli -s=<session> screenshot --filename="$HOME/Downloads/<TICKET_ID>/<state>.png"
```

- The script rewrites SE/FI/NO national-ID-shaped text in text nodes, inputs and same-origin
  iframes to `X`, prints `masked: N`, and exits 1 if the eval did not run. Chain with `&&` so a
  failed mask blocks the capture.
- Run it **immediately before each capture**, after the last navigation, click or re-render. React
  restores the real text on its next render, so one mask per page is not enough.
- `masked: 0` on a page that shows people is a reason to look at the screenshot before uploading it,
  not proof it is clean (an ID can be split across nodes or drawn on a canvas).

## Gotchas found the hard way (Repo sessions)

These are behaviours of this CLI that cost real time to rediscover. Each one produced a false
result — a passing check on broken code, or a failing check on working code — not just a slowdown.

### Timezone

`TZ=<zone> playwright-cli ...` gives a genuinely non-UTC browser. There is no `--timezone` flag and
you do not need one. Combined with `route` mocking this reproduces timezone bugs end to end:

```bash
TZ=America/Los_Angeles playwright-cli -s=tz open http://localhost:3000/...
```

Use a **negative-offset** zone. A positive-offset zone (Europe/Stockholm) leaves most off-by-one
date bugs invisible, so the test passes on broken code.

### Route mocking

- **`route` has no `--method`.** A PUT-only mock has to go through `run-code`.
- **`~` is NOT expanded in `--filename`.** Pass an absolute path or the file lands somewhere
  surprising, or nowhere.
- **Routes installed via `run-code` appear to be cleared by CLI route management** — install them
  after any `goto`, and re-install after each navigation.
- **`requests` output can be minutes stale.** Do not use it to prove a request did or did not
  happen just now.
- RTK Query passes a `Request` object as **arg 0**, so a `window.fetch` wrapper must read method and
  body from `args[0]`, not `args[1]`. Reinstall the wrapper after every `goto`.
- **Mocking is not always the cheapest path.** To verify a threshold in a live app, temporarily move
  the threshold instead of faking data up to it — fewer moving parts and it exercises the real code
  path. Revert afterwards and confirm with `git show HEAD:<file>`. Three attempts at faking a
  16383-char blob through route interception all fell through to a fallback path and proved nothing.

- **End every `route` glob with `*`.** `**/api/x` does not match `/api/x?y=1`; the query string
  defeats the mock and the real backend answers (PROJ-4158). For `ctx.route` in `run-code`, use a
  regex — the `**/path` glob missed ServiceC calls (PROJ-4373).
- **`run-code` routes are untracked and unremovable.** A `page.route(...)` installed via `run-code`
  is not in `route-list`, and `unroute` reports success having removed a *different* CLI route. A
  throwing handler never settles the request, i18n never initialises, and **every page renders
  blank** with no console error. Only `close` + `open` clears it. `require` is undefined there (ESM).
- **`route --body` cannot carry a fixture larger than `ARG_MAX`** (1 MB on macOS); there is no
  `--body-file`. Serve the file from a local CORS-enabled `http.server` instead.
- **A 302 from an https URL to `http://127.0.0.1` is silently not followed** (scheme downgrade).
  `requests` shows `=> [302] Found` and nothing after; i18n falls back to `en`, which reads as a
  locale setting. Assert on the rendered outcome, never on "the route was installed" (PROJ-3890).

### Login without risking a seed-user lockout (Repo)

- **Never live-test a login flow with a real seed user "to see an event".** One failed attempt can
  423-lock a user every worktree shares. Mock the ServiceC login/exchange endpoints instead (PROJ-4373).
- **Local login is OTP-only in the UI.** What works for a real session: in the browser context,
  `POST /api/service-c/v1/usernamepassword/login` through the Vite proxy, then
  `localStorage.loggedIn = "true"` and reload — the refresh-token cookie does the rest (PROJ-4389).
- **External-IdP paths (BankID/GrandID) can still be driven end to end** by routing the ServiceC endpoints
  that wrap the IdP in a Playwright context (PROJ-4420).

### Analytics (PostHog) verification

The recipe — wrap `posthog.capture` through Vite's module graph, headed browser, route PostHog to a
local fulfill — lives in memory `reference_posthog_verify_with_ph_debug`. Two additions: report events
through `ctx.exposeBinding` rather than `window.__events` so they survive the hard reload that
FORCE_LOGOUT does, and loop anything racing a navigation 10x before calling it stable
(PROJ-4327, PROJ-4373).

### Detecting error pages

Match the app's own boundary text ("An unexpected error occurred"), not only React Router's default
error page — a detector with the wrong regex reported `errorPage=false` on the bug itself. Check every
detector against one known-bad screenshot before trusting it (PROJ-4294).

### Toasts and other self-dismissing UI

`react-toastify` autocloses at **5 seconds**. A screenshot poll is slower than that, so you will
record a confident "no toast appeared" for a toast that appeared and left. Either assert within
~1 second, or install a `MutationObserver` that records toast text before you trigger the action.

### Verifying colours and tokens

For a "switching X changes the colours" acceptance criterion, do not eyeball screenshots. Grep the
**token source** to find which value actually differs between the two states, pick the retailer or
theme that shows that difference, then measure **computed styles** via iframe refs. Two themes that
look different can share the token under test.

### Measuring layout and reachability

Verify per element — `scrollIntoView`, then assert the element sits inside both its container box
and the viewport. One bulk measurement at one scroll position flags items that scrolled off the
**top** and makes a working fix look broken.

Echo the value **the page itself reports** (`innerHeight`) from inside the measurement loop. A shell
loop that silently fails to change the viewport produces a run of identical PASSes, which is
indistinguishable from a real pass unless the page states its own size.

### Localhost

See the `reference_playwright_localhost_ipv6_cors` memory — IPv6/CORS resolution on `localhost`
bites in a specific, recurring way.
