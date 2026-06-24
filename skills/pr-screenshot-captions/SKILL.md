---
name: pr-screenshot-captions
description: Caption screenshots that have been uploaded to a GitHub PR description — group them into before/after pairs by step/feature, add a short caption under each explaining what it shows and what it proves, add spacing between them, drop broken/error captures, and collapse intermediate/exploration shots. Verifies each image against the local source files (never captions from filenames alone) and uses a re-fetch-before-write flow to avoid clobbering concurrent edits. Use when a PR has raw uploaded screenshots that need before/after captions, a "Visual Verification Evidence" section, or descriptions added.
autoTrigger:
  - when the user says they added pictures/screenshots to a PR and wants captions / before-after / descriptions / spacing
  - when asked to add a visual verification section to a PR from uploaded images
  - when asked to label, caption, or organize PR screenshots
globs:
  - "**/*"
---

# PR Screenshot Captions — before/after + descriptions

Turns a dump of `<img>` tags a user pasted into a GitHub PR body into a clean, captioned **before → after** evidence section.

## Why this exists / hard rules
- **The PR body is one field — edits race.** The user editing in the browser while you `gh pr edit` means last-write-wins. ALWAYS **re-fetch the body immediately before writing** and diff it against what you last read; only write if unchanged (or reconcile first). When the user adds images, their save often **clobbers a previous description you wrote** — be ready to restore it.
- **Caption from the real images, not filenames.** Open each local source file (Read tool) to confirm what it actually shows. Filenames/alt text lie (a shot named `after-…` may be a browser error page).
- **Be honest about non-evidence.** Drop pure error captures (e.g. "site can't be reached", dev-server error overlays) — they prove nothing and look bad. Collapse intermediate/superseded/exploration shots into a `<details>` block, labeled as such. Don't silently delete a user's images without saying which and why.

## Workflow

1. **Fetch the current body**
   ```bash
   gh pr view <PR> --json body --jq '.body' > /tmp/pr-body.md
   grep -nE '<img|!\[' /tmp/pr-body.md      # inventory images in order
   ```

2. **Match each image to its local source.** GitHub rewrites uploads to `user-attachments/assets/<uuid>` but keeps the original filename in `alt=`. Map `alt` → the local screenshot (e.g. `~/Downloads/<TICKET>-screenshots/<alt>.png`).

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
- Local screenshots for DTF visual work usually live in `~/Downloads/<TICKET>-screenshots/` (see `.dream-team/context.md`).
