---
name: visual-development-workflow
description: Write code, verify it visually in browser or iOS simulator, and iterate based on visual feedback until implementation matches expectations.
---

# Visual Development Workflow

## Overview

This Skill provides a structured workflow for visual development tasks. Claude will write or modify code, verify the result visually using browser screenshots or iOS simulator, compare against design requirements, and iterate until the implementation matches expectations.

**When to invoke this Skill:**
- Implementing new UI components or pages
- Matching designs from mockups or screenshots
- Fixing visual bugs or layout issues
- Refining user interfaces iteratively
- Any task where visual verification is important

## Workflow

### 1. Choose Testing Platform

**IMPORTANT**: Before implementing changes, ask the user which platform(s) to test on using the AskUserQuestion tool:

- **Web (Playwright CLI)**: Desktop/mobile web browser testing (recommended)
- **Web (AppleScript)**: Legacy fallback — AppleScript + screencapture (if Playwright CLI not installed)
- **iOS Simulator** (macOS only): Native iOS app testing
- **Both**: Test on both web and iOS platforms

**Note**: If the user is not on macOS, automatically default to web testing only and inform them that iOS simulator is only available on macOS.

### 2. Implement Changes

- Write or modify the necessary code
- Follow project conventions and best practices
- Use appropriate TypeScript types and component patterns

### 3. Visual Verification (MANDATORY)

**⚠️ IMPORTANT: Pre-Verification Check**

Before running verification tools, **ALWAYS verify the page renders correctly first**:

1. **Check** that the development server is running and the page loads
2. **If the page turns white or shows errors**:
   - Check browser console for errors (`playwright-cli console` or dev server logs)
   - Fix any rendering issues, TypeScript errors, or runtime errors
   - **Do NOT proceed until the page renders correctly**
3. **Why this matters**: Broken pages waste time with any verification method

**Only proceed with verification tools after confirming the page renders correctly.**

Always verify changes visually based on the chosen platform(s):

#### Option A: Web Browser Testing — Playwright CLI (Recommended)

Playwright CLI is the default verification method. It's headless, token-efficient, and auto-generates test code from interactions. Check `dtf-config.json` `verification` field — if set to `"applescript"`, use Option B instead.

```bash
# Detect the dev server port (worktrees use VITE_DEV_PORT from .env.local, main uses 3000)
# S3 translations work on all 3xxx ports (CORS: http://localhost:3*)
PORT=$(grep VITE_DEV_PORT apps/web/.env.local 2>/dev/null | cut -d= -f2 || echo 3000)

# Open browser and navigate (use --headed to watch)
playwright-cli open http://localhost:$PORT/[relevant-path]

# Take a DOM snapshot to get element refs
playwright-cli snapshot

# Interact using refs from snapshot output
playwright-cli click e5
playwright-cli fill e3 "test value"
playwright-cli select e9 "option-value"

# Take screenshot for visual verification
playwright-cli screenshot --filename=verify-feature.png

# Check for console errors
playwright-cli console

# Close when done
playwright-cli close
```

**Multi-agent sessions** — use named sessions to avoid conflicts:
```bash
playwright-cli -s=frontend open http://localhost:$PORT --headed
playwright-cli -s=frontend snapshot
playwright-cli -s=frontend screenshot
```

**Video recording** for PR evidence:
```bash
playwright-cli video-start
# ... perform interactions ...
playwright-cli video-stop feature-demo.webm
```

**Test generation** — every CLI interaction outputs Playwright TypeScript code. Collect the generated code and write it as a test file:
```bash
# Each command outputs code like:
# await page.getByRole('button', { name: 'Submit' }).click();
# Collect these into a .spec.ts file
```

#### Option B: Web Browser Testing — AppleScript (Legacy Fallback)

Use this if Playwright CLI is not installed or `dtf-config.json` has `"verification": "applescript"`. See `~/.claude/projects/-Users-username-Documents/memory/visual-testing.md` for the full AppleScript workflow.

```bash
# Navigate via Chrome
osascript -e 'tell application "Google Chrome" to set URL of active tab of first window to "http://localhost:<PORT>/..."'

# Wait + capture
sleep 4 && osascript -e 'tell application "Google Chrome" to activate' && sleep 0.5 && screencapture -x ~/Downloads/screenshot.png
```

#### Option C: iOS Simulator Testing (macOS only)

```bash
# List available simulators
mcp__ios-simulator__list_simulators

# Start a simulator
mcp__ios-simulator__start_simulator
# Device: iPhone 15 Pro (or user's choice)

# Take screenshot
mcp__ios-simulator__take_screenshot

# Interact with the app
mcp__ios-simulator__tap
mcp__ios-simulator__swipe
```

#### Option D: Both Platforms

Test on web first (Playwright CLI), then iOS simulator, comparing behavior and appearance across both.

### 4. Compare and Analyze

- Compare the screenshot against the design mock or requirements
- Identify specific differences:
  - Layout and spacing issues
  - Color or typography mismatches
  - Missing or incorrect elements
  - Responsive behavior problems

### 5. Iterate

If issues are found:

- Make targeted improvements to address specific problems
- Re-verify with another screenshot
- Repeat until the result matches expectations

### 6. Quality Checks

Once visually satisfied, run standard checks:

```bash
npm run writePrettier  # Format code
npm run lint           # Check linting
npm run type-check     # Verify types
npm run build          # Ensure builds
```

### 7. Commit Changes

When the user approves the result, commit the changes following the git workflow.

## Best Practices

### Visual Comparison Tips

- Take screenshots at the same viewport size as the mock
- Check multiple breakpoints for responsive designs
- Verify interactive states (hover, focus, active)
- Test both light and dark themes if applicable
- Check all relevant pages that might be affected

### Iteration Strategy

- Start with major layout and structure issues
- Then refine spacing, colors, and typography
- Finally polish details like animations and micro-interactions
- Don't be afraid to iterate 2-3 times for best results

### Communication

- Describe what you see in each screenshot
- Explain specific changes made in each iteration
- Highlight remaining issues or differences
- Ask for user feedback when uncertain

## Example Usage

### Example 1: Implementing a Design Mock

```
User: Here's a design for the new login page [provides screenshot]

Claude:
1. Asks about platform preference (Web/iOS/Both)
2. Analyzes the design mock
3. Implements the login page component
4. Takes screenshot of the implementation
5. Compares: "The layout matches, but the button color is slightly off and spacing needs adjustment"
6. Adjusts the code
7. Takes new screenshot
8. Compares: "Now matches the design. The button color and spacing are correct."
9. Runs quality checks
10. Ready for commit
```

### Example 2: Fixing Visual Bug

```
User: The header looks broken on mobile

Claude:
1. Asks about platform preference
2. Connects to browser via Puppeteer
3. Navigates to the page
4. Takes screenshot at mobile viewport
5. Identifies: "The logo is overlapping the menu button"
6. Fixes the CSS flexbox layout
7. Takes new screenshot
8. Verifies: "Layout now works correctly on mobile"
9. Tests at different breakpoints
10. Runs quality checks
```

## Tools Required

### Web Testing (Playwright CLI — Recommended)

- **Playwright CLI**: `npm install -g @playwright/cli@latest` — headless browser automation
- **Development Server**: Must be running (`npm start`)
- **No browser management needed** — Playwright CLI handles its own browser

### Web Testing (AppleScript — Legacy Fallback)

- **Google Chrome**: Must be open with a tab on localhost
- **Development Server**: Must be running (port from `VITE_DEV_PORT` in `.env.local`, defaults to 3000)
- **screencapture**: macOS built-in

### iOS Testing (macOS only)

- **iOS Simulator MCP Server**: For iOS app testing and screenshots
- **Xcode Simulators**: Available iOS simulators on the system
- **Mobile App**: React Native app running in simulator

## Success Criteria

- Visual output matches the design requirements
- All interactive elements work as expected
- Responsive behavior is correct across breakpoints
- Code passes linting, type checking, and builds successfully
- User approves the final result

## Additional Resources

See the resources folder for:
- Platform selection guidelines
- Best practices for visual testing
- Common iteration patterns

## Tips for Claude

- **⚠️ VERIFY PAGE RENDERS FIRST** - Before using Puppeteer/simulator, confirm the page loads correctly in browser; white screens or errors will cause MCP tools to hang indefinitely
- **Always ask about platform preference first** - Use AskUserQuestion at the start to determine if testing web, iOS, or both
- **macOS detection** - Check platform from environment context; iOS simulator only available on macOS
- **Check dev server logs** - Use BashOutput to monitor the development server for errors before taking screenshots
- **Always take before/after screenshots** to show progress
- **Be specific** about what you observe in screenshots
- **Iterate confidently** - first attempts rarely perfect, 2-3 iterations is normal
- **Test interactions** - don't just screenshot, use tap/click and test functionality
- **Check console errors** - use puppeteer_evaluate (web) or appropriate iOS logging
- **Multiple viewports** - test mobile, tablet, and desktop when relevant
- **Cross-platform differences** - When testing both platforms, note any behavioral differences
- **Ask for feedback** - when uncertain, get user input before proceeding

## iOS Safari Login Automation

### Common Pitfalls

**❌ DO NOT use `\n` to submit forms**
- Typing `\n` (newline) in iOS Safari adds literal characters instead of submitting
- This causes forms to be submitted to search engines instead of the intended action
- Example of what happens: URL becomes a Google search query instead of navigating

**❌ Avoid triggering iOS autofill**
- Tapping on username/password fields often triggers iOS password manager prompts
- These prompts block automation and require iPhone passcode entry
- Can completely derail the login flow

### Reliable Login Pattern

Use this step-by-step pattern for iOS Safari form automation:

1. **Navigate to login page**
   - Tap address bar
   - Type full URL (with `http://` if needed to avoid search)
   - Tap on the suggestion (do NOT type `\n`)
   - Wait for page to load

2. **Fill username field**
   - Tap directly on the username input field
   - Type username value
   - If autofill prompt appears, dismiss it by tapping elsewhere or the X button

3. **Fill password field**
   - Tap directly on the password input field
   - Type password value
   - Avoid triggering autofill suggestions

4. **Submit form**
   - Tap the submit/login button directly
   - Do NOT try to submit with keyboard or `\n`

5. **Wait and verify**
   - Use appropriate sleep time (3-4 seconds for network requests)
   - Take screenshot to verify successful login
   - Check for redirect to expected page

### Code Example

```javascript
// Good example of iOS Safari login automation
// Navigate to login page
ui_tap(address_bar)
ui_type("http://localhost:<PORT>/login/userAndPass")
// Tap suggestion instead of typing \n
ui_tap(first_suggestion)
sleep(3)

// Fill username
ui_tap(username_field)
ui_type("gunner")

// Fill password (be careful not to trigger autofill)
ui_tap(password_field)
ui_type("tolvan")

// Submit by tapping button
ui_tap(login_button)
sleep(3)

// Verify
ui_view()
```

### Troubleshooting

**Problem: Forms submit to Google instead of navigating**
- Cause: Used `\n` to submit or didn't include `http://` in URL
- Solution: Tap suggestions or buttons directly, use full URLs

**Problem: iPhone passcode prompt appears**
- Cause: iOS autofill was triggered
- Solution: Dismiss the prompt, clear fields, and try again without triggering autofill

**Problem: Typed in wrong field**
- Cause: Didn't wait for keyboard to appear or tapped wrong coordinates
- Solution: Add sleep(1) after tapping field, verify field is focused

**Problem: Button tap doesn't work**
- Cause: Button is disabled or coordinates are wrong
- Solution: Take screenshot first to verify button state and position

### Best Practices

- **Always use `ui_view()` to verify state** before and after actions
- **Add appropriate sleep times** (1s after taps, 3-4s after navigation)
- **Use suggestions over typing submit keys** - more reliable in iOS Safari
- **Be explicit with coordinates** - verify with screenshots first
- **Test manually first** - ensure the page works before automating
- **Handle autofill gracefully** - have a plan to dismiss prompts
- **Use full URLs with protocol** - prevents search engine redirects
