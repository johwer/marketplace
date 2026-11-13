---
name: pr-screenshot-captions
description: Caption screenshots uploaded to a GitHub PR as before/after pairs under Visual verification, checked against the local source files, plus the rules for taking PR screenshots. Use when a PR has raw uploaded images that need captions, grouping or a visual verification section, or when screenshots for a PR are about to be captured.
---

# PR Screenshot Captions — before/after + descriptions

Turns a dump of `<img>` tags a user pasted into a GitHub PR body into a clean, captioned **before → after** evidence section.

## Why this exists / hard rules
- **The PR body is one field — edits race.** The user editing in the browser while you `gh pr edit` means last-write-wins. ALWAYS **re-fetch the body immediately before writing** and diff it against what you last read; only write if unchanged (or reconcile first). When the user adds images, their save often **clobbers a previous description you wrote** — be ready to restore it.
- **Caption from the real images, not filenames.** Open each local source file (Read tool) to confirm what it actually shows. Filenames/alt text lie (a shot named `after-…` may be a browser error page).
- **Label deliberately forced failures.** A 503/403 forced through a playwright route reads as a
  broken flow. Caption it "Avsiktligt framtvingat fel" (or "Deliberately forced error") and group it
  under a collapsed error-handling heading (PROJ-4752).
- **Be honest about non-evidence.** Drop pure error captures (e.g. "site can't be reached", dev-server error overlays) — they prove nothing and look bad. Collapse intermediate/superseded/exploration shots into a `<details>` block, labeled as such. Don't silently delete a user's images without saying which and why.

## Capturing the shots (before they reach the PR)
- **Market locale.** Render in the feature's market language (`localStorage.setItem("mh_lang", "sv")` in an init script for a Swedish feature) so labels and dates read right to the PO.
- **Scroll to the change.** `scrollIntoView({block:'center'})`, then a viewport shot for context plus an element shot for detail.
- **Mobile (390px) only where the Employee role is the audience** (own service-a, own profile, self-service); HR/admin flows get desktop only.
- **Save to `~/Downloads/<TICKET>/`**, never `/tmp` or the repo. Only `toHaveScreenshot()` baselines that a test references are ever committed.
- **Look at each shot right after taking it.** If it doesn't visibly show what its filename claims, flag it and re-capture; never hand over unchecked shots or drop screenshots instead. For a URL/redirect/query-param change, make the URL visible in the capture (a stand-in page that renders what it received, or an on-page `location.href` banner).
- **Never overwrite a shot already handed to someone.** Re-takes get a new name (`04-outcome-v2.png`). On a publish conflict for a shared artifact, diff against the live version: identical means skip, different means merge, never force.

## Workflow

1. **Fetch the current body**
   ```bash
   gh pr view <PR> --json body --jq '.body' > /tmp/pr-body.md
   grep -nE '<img|!\[' /tmp/pr-body.md      # inventory images in order
   ```

2. **Match each image to its local source.** GitHub rewrites uploads to `user-attachments/assets/<uuid>` but keeps the original filename in `alt=`. Map `alt` → the local screenshot (e.g. `~/Downloads/<TICKET>/<alt>.png`).

3. **Verify by opening the files.** Read each local image. Classify it:
   - **evidence** (a real before or after of a step/feature) → keep + caption
   - **broken** (error page, blank, dev-server overlay) → drop (note it)
   - **intermediate / superseded / exploration / duplicate** → collapse in `<details>`

4. **Group into before → after pairs by step/feature.** Reorder within the user's image block so each `before` is immediately followed by its `after`. Use `###` section headers (Step 1 — Colors, etc.).

5. **Caption every kept image.** One line under each (or under each pair) saying **what it shows** and **what it proves**. Add a blank line / `<br />` between images so they don't cram. Separate sections with `---`.

6. **Preserve user content + restore any clobbered summary.** Keep the user's other prose. If their image-upload overwrote a description you wrote earlier, paste it back below the evidence.

7. **Re-fetch and write back**
   ```bash
   gh pr view <PR> --json body --jq '.body' > /tmp/pr-recheck.md
   diff -q /tmp/pr-body.md /tmp/pr-recheck.md   # if changed, reconcile before writing
   gh pr edit <PR> --body-file /tmp/pr-new-body.md
   ```

8. **Verify the result:** image count is sensible, dropped shots are gone, sections render.

## Walkthrough video (flow changes)
A flow change has a `walkthrough-<flow>.webm` in `~/Downloads/<TICKET_ID>/` next to the stills. The user drags it into the PR like the images; GitHub turns it into a bare `https://github.com/user-attachments/assets/<uuid>` line that plays inline (no `<img>`, no alt, so match it by order and by asking, not by filename).
- Put it **first** inside `## Visual verification`, under `### Walkthrough`, above the captioned stills. One `### Walkthrough — <flow>` per video when there are several.
- The URL stays on its own line with blank lines around it, or GitHub shows a link instead of a player.
- Caption it like a still: one quote line with the scripted path, then what it **proves**. Caption from what the video shows, not from the filename. You can't watch it, so caption from the recorded script and its `video-chapter` steps, and ask the user to confirm the video matches.
- Keep the key states as captioned stills below it: the video shows motion, the stills are what a reviewer scans.

```markdown
### Walkthrough

https://github.com/user-attachments/assets/<uuid>

> ↓ through every slide and on to "More insights", ↑ back up, then a click on a dimmed slide. Proves the focus follows the keys and the click, and that the keys let go at the last slide.
```

## Caption shape (example)
```markdown
### Step 1 — Colors
<img width="850" alt="before-step1-colors" src="…" />
<img width="850" alt="after-step1-colors"  src="…" />

> Old dark-green / cream palette → new dark-teal `#0C2524` + white/grey surfaces. Proves the token swap landed across every swatch.
```

## Sizing
- Full desktop shots: `width="850"`. Mobile (≤400px wide): `width="260"`. Close-ups: `width="380"`.
- GitHub scales to the container; setting width keeps before/after visually comparable and stops one giant image dominating.

## Notes
- This pairs with DTF's `my-dream-team` Phase 6 "screenshot-caption check" (mark-ready step) — same intent, reusable on demand.
- Local screenshots for DTF visual work live in `~/Downloads/<TICKET>/` (see `.dream-team/context.md`).
