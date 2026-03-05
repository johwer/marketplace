# Workspace Launch — Create Worktree & Start Dream Team

You are setting up a new development workspace from a Jira ticket.

## Config Resolution

Read `~/.claude/dtf-config.json` if it exists. Use:
- `paths.monorepo` instead of `~/Documents/MedHelp`
- `paths.worktreeParent` instead of `~/Documents`
- `terminal` instead of the hardcoded terminal name
If no config exists, fall back to the values in `~/.claude/CLAUDE.md`.

## Input

The user provides either:
- A **ticket ID** (e.g., `PLRS-1234`)
- An **image/screenshot** of a ticket (fallback if ACLI is unavailable)

$ARGUMENTS

## Workflow

### Step 1: Fetch Ticket from Jira

**Primary method — ACLI CLI:**

Try fetching the ticket details using the ACLI Jira CLI:

```bash
acli jira workitem view <TICKET_ID>
```

If successful, extract:
- **Ticket ID**
- **Summary/title**
- **Description** — capture the full description
- **Acceptance criteria** — if present
- **Attachments** — note any attachment names and URLs

If ACLI is not installed or the command fails, fall back to reading the provided image/screenshot.

**Fallback — Image extraction:**

If an image was provided instead of a ticket ID, read it carefully and extract:
- **Ticket ID** (e.g., `PLRS-1234`)
- **Ticket title/description** — capture ALL rows/details visible in the image

### Step 2: Handle Attachments

If the ticket has attachments (design mockups, specs, etc.):

1. List the attachments and their URLs to the user
2. Open each attachment in Chrome for authenticated download:
   ```bash
   open -a "Google Chrome" "<ATTACHMENT_URL>"
   ```
3. Tell the user where Chrome will download the files (`~/Downloads/` — shown as "Hämtade filer" on Swedish macOS)
4. Ask the user to confirm once downloads are complete
5. Read any downloaded images/PDFs to understand the full ticket context

**Note:** Do NOT use `curl` or `wget` for Jira attachments — they require browser authentication and will return 401 Unauthorized.

### Step 3: Confirm with User

Present the extracted ticket info to the user for confirmation before proceeding:
- Ticket ID
- Title
- Full description
- Attachments (if any)

### Step 4: Create Git Worktree

```bash
cd ~/Documents/MedHelp
git worktree add ~/Documents/<TICKET_ID> -b <TICKET_ID>
```

Replace `<TICKET_ID>` with the ticket ID (e.g., `PLRS-1234`).

If the branch already exists, use:
```bash
git worktree add ~/Documents/<TICKET_ID> <TICKET_ID>
```

### Step 5: Install Dependencies

Run in the new worktree:

```bash
cd ~/Documents/<TICKET_ID>/apps/web && source ~/.nvm/nvm.sh && nvm use && npm i
```

### Step 6: Generate Environment Files

Run the port allocation script from the worktree. It generates both `.env` (root) and `apps/web/.env.local` with unique ports:

```bash
~/Documents/<TICKET_ID>/scripts/allocate-ports.sh <TICKET_ID>
```

The script:
- Derives a port slot from the ticket number (deterministic)
- Checks for collisions with other active worktrees and bumps if needed
- Assigns ports in the 10000+ range (never conflicts with main stack's 500x)
- Writes both env files

Show the user the output — it lists all assigned ports.

### Step 7: Launch Claude in New Terminal

This uses the self-contained launcher script at `~/.claude/scripts/launch-workspace.sh` which handles everything: cd, unset CLAUDECODE, start tmux, launch Claude, and attach.

**Check the user's terminal preference** in `~/.claude/CLAUDE.md` under "Workspace Preferences" for the configured terminal app. Then open a new window running the launcher script:

```bash
bash ~/.claude/scripts/open-terminal.sh "<TERMINAL_APP>" "bash ~/.claude/scripts/launch-workspace.sh '<TICKET_ID>'"
```

Replace `<TERMINAL_APP>` with the configured app (Alacritty, Terminal, iTerm, Warp, Kitty, WezTerm, or Ghostty).

### Step 8: Provide Dream Team Instructions

Tell the user to run the following command in the new Claude session:

```
/my-dream-team <paste the full ticket description>
```

Display the full extracted ticket text (including description, acceptance criteria, and attachment context) so the user can copy-paste it.

## Important Rules

- Always confirm the extracted ticket ID with the user before creating the worktree
- The main repo is always at `~/Documents/MedHelp`
- Worktrees are always created at `~/Documents/<TICKET_ID>`
- If anything fails, stop and report the error — do not continue blindly
- After setup is complete, remind the user they can run `/workspace-cleanup <TICKET_ID>` when done
- Prefer ACLI Jira CLI over image screenshots when a ticket ID is available
- Never use curl/wget for Jira attachments — always use Chrome for authenticated access
