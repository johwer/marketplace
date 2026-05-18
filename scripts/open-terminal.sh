#!/bin/bash
# Open a command in a new terminal window using the user's preferred terminal app.
# Usage: open-terminal.sh <TERMINAL_APP> <COMMAND>
#
# Supported terminals (10):
#   Cross-platform: Alacritty, Kitty, WezTerm, Ghostty, Warp
#   macOS only:     Terminal, iTerm
#   Linux only:     GNOME-Terminal, Konsole
#   Windows (WSL):  Windows-Terminal
#
# Example:
#   open-terminal.sh Alacritty "bash ~/.claude/scripts/launch-workspace.sh PROJ-1234"

TERMINAL_APP="$1"
shift
COMMAND="$*"

SUPPORTED="Alacritty, Terminal, iTerm, Warp, Kitty, WezTerm, Ghostty, GNOME-Terminal, Konsole, Windows-Terminal"

if [ -z "$TERMINAL_APP" ] || [ -z "$COMMAND" ]; then
  echo "Usage: open-terminal.sh <TERMINAL_APP> <COMMAND>"
  echo "Supported: $SUPPORTED"
  exit 1
fi

OS="$(uname -s)"

# Platform guard for macOS-only terminals
require_macos() {
  if [ "$OS" != "Darwin" ]; then
    echo "Error: $TERMINAL_APP is macOS only (detected: $OS)"
    echo "Cross-platform alternatives: Alacritty, Kitty, WezTerm, Ghostty, Warp"
    exit 1
  fi
}

# Platform guard for Linux-only terminals
require_linux() {
  if [ "$OS" != "Linux" ]; then
    echo "Error: $TERMINAL_APP is Linux only (detected: $OS)"
    echo "Cross-platform alternatives: Alacritty, Kitty, WezTerm, Ghostty, Warp"
    exit 1
  fi
}

# Write COMMAND to a temp script to avoid quote-stripping in nested bash -c shells.
# mktemp template must end with X's (no .sh suffix) to work on macOS.
make_tmpscript() {
  local tmp
  tmp="$(mktemp /tmp/terminal-launch-XXXXXX)"
  printf '#!/bin/bash\n%s\n' "$COMMAND" > "$tmp"
  chmod +x "$tmp"
  echo "$tmp"
}

# Bring the terminal window to the foreground after launching it.
# Cross-platform terminals (Alacritty, Kitty, WezTerm, Ghostty) spawn detached
# and stay behind other windows on macOS — this raises them so the user sees
# the new tmux session without alt-tabbing. No-op on Linux/Windows.
raise_terminal_app() {
  local app="$1"
  [ "$OS" != "Darwin" ] && return 0
  # Small delay so the app process is registered with the WindowServer
  # before we try to activate it.
  ( sleep 0.4 && osascript -e "tell application \"$app\" to activate" >/dev/null 2>&1 ) &
}

case "$TERMINAL_APP" in

  # --- Cross-platform ---

  Alacritty)
    TMPSCRIPT="$(make_tmpscript)"
    alacritty -e "$TMPSCRIPT" &
    raise_terminal_app "Alacritty"
    ;;

  Warp)
    if [ "$OS" = "Darwin" ]; then
      osascript -e "tell application \"Warp\"
    activate
    delay 0.5
end tell
tell application \"System Events\"
    tell process \"Warp\"
        keystroke \"t\" using {command down}
        delay 0.3
        keystroke \"$COMMAND\"
        key code 36
    end tell
end tell"
    else
      # Linux: Warp supports CLI launch
      TMPSCRIPT="$(make_tmpscript)"
      warp-terminal -e "$TMPSCRIPT" &
    fi
    ;;

  Kitty)
    TMPSCRIPT="$(make_tmpscript)"
    kitty --detach "$TMPSCRIPT"
    raise_terminal_app "kitty"
    ;;

  WezTerm)
    TMPSCRIPT="$(make_tmpscript)"
    wezterm start -- "$TMPSCRIPT" &
    raise_terminal_app "WezTerm"
    ;;

  Ghostty)
    TMPSCRIPT="$(make_tmpscript)"
    ghostty -e "$TMPSCRIPT" &
    raise_terminal_app "Ghostty"
    ;;

  # --- macOS only ---

  Terminal)
    require_macos
    osascript -e "tell application \"Terminal\"
    activate
    do script \"$COMMAND\"
end tell"
    ;;

  iTerm|iTerm2)
    require_macos
    osascript -e "tell application \"iTerm\"
    activate
    set newWindow to (create window with default profile)
    tell current session of newWindow
        write text \"$COMMAND\"
    end tell
end tell"
    ;;

  # --- Linux only ---

  GNOME-Terminal)
    require_linux
    TMPSCRIPT="$(make_tmpscript)"
    gnome-terminal -- bash -c "$TMPSCRIPT; exec bash"
    ;;

  Konsole)
    require_linux
    TMPSCRIPT="$(make_tmpscript)"
    konsole -e bash -c "$TMPSCRIPT; exec bash" &
    ;;

  # --- Windows (WSL) ---

  Windows-Terminal)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      # Inside WSL: use cmd.exe to open a new Windows Terminal tab running in WSL
      TMPSCRIPT="$(make_tmpscript)"
      cmd.exe /c "wt.exe -w 0 nt wsl.exe bash -c \"$TMPSCRIPT\"" &
    else
      echo "Error: Windows-Terminal is only supported inside WSL (Windows Subsystem for Linux)"
      echo "Cross-platform alternatives: Alacritty, Kitty, WezTerm, Ghostty"
      exit 1
    fi
    ;;

  *)
    echo "Unsupported terminal: $TERMINAL_APP"
    echo "Supported: $SUPPORTED"
    exit 1
    ;;
esac
