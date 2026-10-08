#!/bin/bash
#
# Purpose: Check what Doorbell needs on this Mac and send one test alert.
# Inputs:  None. CLAUDE_PLUGIN_DATA, when set, points at the plugin's data directory.
# Outputs: A checklist on stdout. Exit code 1 when a check failed, 0 otherwise.

HERE=$(cd "$(dirname "$0")" && pwd)
VSCODE_STATE="$HOME/Library/Application Support/Code/User/globalStorage/storage.json"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

failures=0
ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

echo "Doorbell check"

if [ "$(uname -s)" != "Darwin" ]; then
  fail "Doorbell works on macOS only; this machine runs $(uname -s)."
  exit 1
fi

# The same PATH the hook script gives itself, so both find the same tools.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

if command -v jq >/dev/null 2>&1; then
  ok "jq found"
else
  fail "jq is missing, so no alert can be built. Install it: brew install jq"
fi

# The default sounds. A name set in the options that does not exist falls back to these
# when an alert is sent, and the log says so.
for sound in Funk Glass Basso; do
  if [ -f "/System/Library/Sounds/$sound.aiff" ]; then
    ok "sound $sound found"
  else
    fail "the system sound $sound is missing from /System/Library/Sounds"
  fi
done

NOTIFIER=$(command -v terminal-notifier 2>/dev/null)

if [ -z "$NOTIFIER" ]; then
  warn "terminal-notifier is not installed: banners appear, but a click cannot open the chat."
  warn "Install it: brew install terminal-notifier"
else
  version=$("$NOTIFIER" -version 2>&1 | head -n 1 | sed -E 's/^[^0-9]*([0-9][0-9.]*[0-9]).*$/\1/')
  ok "terminal-notifier found (version ${version:-unknown})"
  case "$version" in
    [012].*) warn "Doorbell is tested with terminal-notifier 3; this is an older one. Update it: brew upgrade terminal-notifier" ;;
  esac
  diagnosis=$("$NOTIFIER" -diagnose 2>&1)
  value_of() { printf '%s\n' "$diagnosis" | sed -n "s/^ *$1  *//p" | head -n 1; }
  case "$(value_of authorization)" in
    authorized*)
      ok "terminal-notifier may show notifications"
      case "$(value_of 'alert style')" in
        none*)    warn "Its alert style is None, so nothing appears on screen. Choose Temporary or Persistent in System Settings > Notifications > terminal-notifier." ;;
        banners*) ok "banners disappear after a few seconds (choose Persistent in System Settings > Notifications > terminal-notifier to keep them until dismissed)" ;;
        alerts*)  ok "banners stay on screen until dismissed" ;;
      esac ;;
    denied*)
      fail "Notifications for terminal-notifier are turned off."
      warn "Turn them on: System Settings > Notifications > terminal-notifier > Allow notifications." ;;
    "not requested"*)
      # macOS shows its permission prompt only for an app launched through LaunchServices;
      # called from a hook, terminal-notifier is refused without ever asking.
      app=$(value_of 'bundle path')
      if [ -d "$app" ]; then
        "$LSREGISTER" -f "$app" >/dev/null 2>&1
        open -n -a "$app" --args -title "Doorbell" -message "Allow notifications to see Doorbell banners." >/dev/null 2>&1
      fi
      warn "macOS has not been asked yet whether terminal-notifier may show notifications."
      warn "It should ask now: choose Allow, then run this check again." ;;
    *)
      warn "Could not read the notification permission. If no banner appears below, check System Settings > Notifications > terminal-notifier." ;;
  esac
fi

if [ -r "$VSCODE_STATE" ]; then
  ok "VS Code window list found (a click on a banner can pick the right window)"
else
  warn "VS Code's window list was not found: a click brings VS Code forward but cannot pick the window."
fi

DATA_DIR="${CLAUDE_PLUGIN_DATA:-}"
if [ -z "$DATA_DIR" ]; then
  for candidate in "$HOME/.claude/plugins/data/doorbell-slavic-sensei" "$HOME/.claude/doorbell"; do
    [ -d "$candidate" ] && DATA_DIR="$candidate" && break
  done
fi
export CLAUDE_PLUGIN_DATA="${DATA_DIR:-$HOME/.claude/doorbell}"
LOG_FILE="$CLAUDE_PLUGIN_DATA/doorbell.log"

if command -v jq >/dev/null 2>&1; then
  echo
  echo "Sending a test alert with the default sound and English text (your options apply to real alerts)..."
  jq -n --arg cwd "$PWD" '{hook_event_name: "Stop", session_id: "doorbell-doctor", cwd: $cwd,
        last_assistant_message: "Doorbell test: if you heard a sound and can read this, alerts work. A click brings VS Code forward."}' \
    | bash "$HERE/notify.sh"
  # Other sessions write to the same log; read the line of the test session only.
  result=$(grep ' doorbell Stop ' "$LOG_FILE" 2>/dev/null | tail -n 1 \
           | sed -E 's/^.* (alerted|skipped|muted|ignored)/\1/')
  case "$result" in
    alerted*"via none"*)
      fail "No banner could be shown ($result)." ;;
    alerted*"via osascript"*)
      ok "$result"
      # osascript reports success whether or not macOS shows the banner.
      warn "The banner was sent through Script Editor, and macOS does not say whether it showed it. If you saw none, allow notifications in System Settings > Notifications > Script Editor." ;;
    alerted*)
      ok "$result" ;;
    *)
      warn "The test alert was not sent: ${result:-nothing was logged}." ;;
  esac
fi

echo
echo "Log: $LOG_FILE"
[ "$failures" -eq 0 ]
