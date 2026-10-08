#!/bin/bash
#
# Purpose: Tell the user, by sound and macOS banner, that a Claude Code session needs them
#          or has finished. One script serves every hook event listed in hooks/hooks.json.
# Inputs:  Hook JSON on stdin (hook_event_name, session_id, cwd and event-specific fields);
#          options as CLAUDE_PLUGIN_OPTION_* environment variables (declared in plugin.json).
# Outputs: A sound, a banner and one line in the log. Nothing on stdout or stderr and exit
#          code always 0: Claude Code reads hook output, and an alert must never change what
#          a session does.

# Sounds and banners below are macOS tools; stay silent in remote and container sessions.
[ "$(uname -s)" = "Darwin" ] || exit 0
# A hook inherits the PATH of the app that started Claude Code, which often lacks the
# Homebrew prefixes where jq and terminal-notifier may live.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
command -v jq >/dev/null 2>&1 || exit 0

export LC_ALL=en_US.UTF-8   # cut, sed and tr must count characters, not bytes

DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/doorbell}"
STATE_DIR="$DATA_DIR/state"
LOG_FILE="$DATA_DIR/doorbell.log"
VSCODE_BUNDLE="com.microsoft.VSCode"
VSCODE_STATE="${DOORBELL_VSCODE_STATE:-$HOME/Library/Application Support/Code/User/globalStorage/storage.json}"

DEDUPE_SECONDS=2   # one prompt raises PreToolUse and PermissionRequest in the same moment
ECHO_SECONDS=10    # ...and, if still unanswered, a Notification about six seconds later
                   # (5 to 7 s measured in the VS Code extension 2.1.292)
FOCUS_PAUSE=1      # seconds a clicked banner waits for the window switch before it asks
                   # that window for the chat

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
# Nothing may reach Claude Code. Unexpected shell errors go to the log, or nowhere when the
# log cannot be written.
exec >/dev/null
if { : >>"$LOG_FILE"; } 2>/dev/null; then exec 2>>"$LOG_FILE"; else exec 2>/dev/null; fi

# A plugin option. Claude Code exports only the options the user has set, so the defaults
# live here and not in plugin.json alone.
option() { local name="CLAUDE_PLUGIN_OPTION_$1"; printf '%s' "${!name:-$2}"; }
is_on() { case "$1" in 1|true|TRUE|True|yes|on) return 0 ;; *) return 1 ;; esac; }

LANGUAGE=$(option LANGUAGE en)
MUTE=$(option MUTE false)
SPEAK=$(option SPEAK false)
VOICE=$(option VOICE "")
SOUND_ATTENTION=$(option SOUND_ATTENTION Funk)   # names from /System/Library/Sounds
SOUND_DONE=$(option SOUND_DONE Glass)
SOUND_ERROR=$(option SOUND_ERROR Basso)
MIN_DONE_SECONDS=$(option MIN_DONE_SECONDS 10)   # after a shorter turn the user has most likely not looked away yet
case "$MIN_DONE_SECONDS" in
  ''|*[!0-9.]*|*.*.*|.) MIN_DONE_SECONDS=10 ;;   # not a number
  *.*) MIN_DONE_SECONDS=${MIN_DONE_SECONDS%%.*}; MIN_DONE_SECONDS=${MIN_DONE_SECONDS:-0} ;;   # 2.5 -> 2, .5 -> 0
esac
[ "${#MIN_DONE_SECONDS}" -le 6 ] || MIN_DONE_SECONDS=999999

# To add a language, copy a block and translate it.
case "$LANGUAGE" in
  cs)
    T_DONE="Hotovo — čeká na tebe";       T_ERROR="Zastaveno chybou"
    T_PERMISSION="Čeká na schválení";     T_QUESTION="Má na tebe otázku"
    T_PLAN="Plán čeká na schválení";      T_MCP="MCP server žádá vstup"
    T_WAITING="Čeká na tebe";             T_OPEN="Pokračuj v chatu"
    T_PAUSED="Pozastaveno — na pozadí se ještě pracuje"
    S_ATTENTION="čeká na tebe";           S_DONE="hotovo";    S_ERROR="chyba"
    DEFAULT_VOICE="Zuzana" ;;
  *)
    T_DONE="Finished — waiting for you";  T_ERROR="Stopped by an error"
    T_PERMISSION="Needs your approval";   T_QUESTION="Has a question for you"
    T_PLAN="Plan ready for review";       T_MCP="MCP server asks for input"
    T_WAITING="Waiting for you";          T_OPEN="Open the chat to continue"
    T_PAUSED="Paused — background work is still running"
    S_ATTENTION="needs you";              S_DONE="finished";  S_ERROR="error"
    DEFAULT_VOICE="" ;;   # empty = the system voice
esac
VOICE=${VOICE:-$DEFAULT_VOICE}

NOTIFIER=$(command -v terminal-notifier 2>/dev/null)

input=$(cat)
field() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }

event=$(field .hook_event_name)
session=$(field .session_id | tr -cd 'A-Za-z0-9_-')
session=${session:-unknown}
entrypoint=${CLAUDE_CODE_ENTRYPOINT:-unknown}
project_dir=${CLAUDE_PROJECT_DIR:-$(field .cwd)}
project=$(basename "${project_dir:-unknown}" | tr -d '[:cntrl:]')
detail=""   # tool name, notification type or error type; message texts never go to the log

# One line per decision. Names of directories, tools and servers come from outside, so
# control characters are removed: a name with a line break in it must not be able to write a
# line of its own.
log() {
  local line
  line=$(printf '%s  %-8.8s %-17s %-20.20s %-24.24s %-13s %s' \
    "$(date '+%F %T')" "$session" "$event" "${detail:--}" "$project" "$entrypoint" "$1" | tr -d '[:cntrl:]')
  printf '%s\n' "$line" >>"$LOG_FILE"
}

now=$(date +%s)
age_of() { echo $(( now - $(/usr/bin/stat -f %m "$1" 2>/dev/null || echo 0) )); }

# Headless runs (claude -p, SDK scripts, cron jobs) have nobody waiting at a window.
case "$entrypoint" in
  sdk-*) log "skipped: headless"; exit 0 ;;
esac

# Three small files per session tell what kind of turn is ending when Stop arrives:
#   <session>.start    its time is when the turn began that the user is waiting for
#   <session>.working  a turn is in progress
#   <session>.waking   the turn ended, but background work will wake the session up again
if [ "$event" = "UserPromptSubmit" ]; then
  # Claude Code raises this event not only for a prompt somebody typed. It also raises it for
  # a message typed while Claude is still working, for background work reporting back and
  # for a scheduled task. Only a prompt that starts a turn in an idle session starts the
  # clock; otherwise the end of a long piece of work could pass for a short turn. Background
  # work is known by the mark its turn left behind, or by the notice Claude Code wraps its
  # report in; either is enough, because a ring too many is better than a ring too few.
  report=$(jq -r '(.prompt // "")[0:400] | contains("<task-notification>")' <<<"$input" 2>/dev/null)
  if [ -f "$STATE_DIR/$session.working" ]; then
    :   # in the middle of a turn: the turn keeps its start
  elif [ -f "$STATE_DIR/$session.waking" ] || [ "$report" = "true" ]; then
    rm -f "$STATE_DIR/$session.waking"   # background work reporting back: the same work goes on
  else
    : >"$STATE_DIR/$session.start"
  fi
  : >"$STATE_DIR/$session.working"
  [ -n "$NOTIFIER" ] && "$NOTIFIER" -remove "doorbell-$session" 2>/dev/null
  /usr/bin/find "$STATE_DIR" -type f -mtime +2 -delete 2>/dev/null
  /usr/bin/find "$STATE_DIR" -mindepth 1 -type d -name '*.mutex' -mtime +1 -exec rmdir {} + 2>/dev/null
  if [ "$(wc -l <"$LOG_FILE")" -gt 2000 ]; then
    tail -n 1000 "$LOG_FILE" >"$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
  exit 0
fi

case "$event" in
  Stop)
    rm -f "$STATE_DIR/$session.working"
    kind="done"; subtitle="$T_DONE"
    body=$(field .last_assistant_message)
    # Agents or workflows the turn started are still running and will wake the session up
    # again: it is paused, not finished, and nobody is needed yet. That gets a banner but no
    # ring. Only these two kinds of task count, because they are the ones seen to report
    # back. A shell command may be a server that runs for good, and a teammate may idle for
    # as long as its team lives; taking those for a pause would silence the bell for good.
    waiting=$(jq -r '[.background_tasks[]? | select(.type == "subagent" or .type == "workflow")] | length' \
              <<<"$input" 2>/dev/null)
    if [ "${waiting:-0}" -gt 0 ]; then
      kind="paused"; subtitle="$T_PAUSED"; detail="$waiting in background"
      : >"$STATE_DIR/$session.waking"
    fi ;;
  StopFailure)
    rm -f "$STATE_DIR/$session.working"
    kind="error"; subtitle="$T_ERROR"
    detail=$(field .error)
    # For this event the field holds the error text Claude Code displayed, not a reply.
    body=$(field .last_assistant_message); body=${body:-$detail} ;;
  PermissionRequest)
    kind="attention"; subtitle="$T_PERMISSION"
    detail=$(field .tool_name)
    # Questions and plans arrive through PreToolUse with a better text; skip their twin here.
    case "$detail" in
      AskUserQuestion|ExitPlanMode) log "ignored: covered by PreToolUse"; exit 0 ;;
    esac
    # The description or file name, never the command itself: a command can carry a secret.
    body=$(field '.tool_input.description // .tool_input.file_path')
    body="$detail${body:+: $body}" ;;
  PreToolUse)
    kind="attention"; detail=$(field .tool_name)
    case "$detail" in
      AskUserQuestion) subtitle="$T_QUESTION"; body=$(field '.tool_input.questions[0].question') ;;
      ExitPlanMode)    subtitle="$T_PLAN"; body="" ;;
      *) exit 0 ;;
    esac ;;
  Elicitation)
    kind="attention"; subtitle="$T_MCP"
    detail=$(field .mcp_server_name)
    body=$(field .message); body="$detail${body:+: $body}" ;;
  Notification)
    # The fallback for what raises no event of its own: a sandboxed command's network
    # request, and a wait for a usage limit that ended without the task being continued.
    detail=$(field .notification_type); body=$(field .message)
    case "$detail" in
      permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input|quota_auto_resume_stale|quota_auto_resume_disabled)
        kind="attention"; subtitle="$T_WAITING" ;;
      agent_completed)
        kind="done"; subtitle="$T_DONE" ;;
      *) log "ignored"; exit 0 ;;   # idle_prompt only repeats what Stop already announced
    esac ;;
  *) exit 0 ;;
esac

turn_note=""
if { [ "$kind" = "done" ] || [ "$kind" = "paused" ]; } && [ -f "$STATE_DIR/$session.start" ]; then
  elapsed=$(age_of "$STATE_DIR/$session.start")
  # A negative time means the clock was set back; then nothing is known about the turn.
  if [ "$elapsed" -ge 0 ]; then
    # Both numbers go to the log, whatever the decision: the limit is an option, and only
    # the log can show which value a session is really using.
    turn_note="turn took ${elapsed}s (limit ${MIN_DONE_SECONDS}s)"
    if [ "$elapsed" -lt "$MIN_DONE_SECONDS" ]; then
      log "skipped: $turn_note"; exit 0
    fi
    turn_note=", $turn_note"
  fi
fi

# One alert per prompt: of the events one prompt raises, only the first may alert. The time
# of a session's last alert of a kind is the modification time of a stamp file. A
# Notification about a prompt is the late echo of a prompt already announced, so it is held
# back for longer; it still alerts on its own when nothing announced the prompt before it.
window="$DEDUPE_SECONDS"
[ "$event" = "Notification" ] && [ "$kind" = "attention" ] && window="$ECHO_SECONDS"
stamp="$STATE_DIR/$session.$kind.last"
mutex="$stamp.mutex"

# Hook processes of one session start within milliseconds of each other, so reading and
# renewing the stamp has to be one step. mkdir is atomic. A mutex left behind by a killed
# process is cleared after five seconds, and when the mutex cannot be had at all the alert
# goes out anyway: a second ring is better than none.
arrived=$now; held=0; tries=0
while [ "$tries" -lt 40 ]; do
  if mkdir "$mutex" 2>/dev/null; then held=1; break; fi
  made=$(/usr/bin/stat -f %m "$mutex" 2>/dev/null) && [ $((arrived - made)) -ge 5 ] && rmdir "$mutex" 2>/dev/null
  tries=$((tries + 1))
  sleep 0.05
done
# The question is whether somebody alerted shortly before this event arrived or at any time
# since, however long the wait for the mutex took. A stamp later than the present moment is
# a clock that was set back, not an alert.
now=$(date +%s)
alerted=$(/usr/bin/stat -f %m "$stamp" 2>/dev/null)
duplicate=0
if [ -n "$alerted" ] && [ "$alerted" -le "$now" ] && [ $((arrived - alerted)) -lt "$window" ]; then
  duplicate=1
else
  : >"$stamp"
fi
[ "$held" = 1 ] && rmdir "$mutex" 2>/dev/null
if [ "$duplicate" = 1 ]; then
  log "skipped: duplicate"; exit 0
fi

if is_on "$MUTE"; then
  log "muted: $kind"; exit 0
fi

case "$kind" in
  attention) sound="$SOUND_ATTENTION"; default_sound="Funk";  spoken="$S_ATTENTION" ;;
  done)      sound="$SOUND_DONE";      default_sound="Glass"; spoken="$S_DONE" ;;
  error)     sound="$SOUND_ERROR";     default_sound="Basso"; spoken="$S_ERROR" ;;
  paused)    sound="";                 default_sound="";      spoken="" ;;   # a banner, no ring
esac
sound_note=""
if [ -n "$default_sound" ]; then
  sound=$(printf '%s' "$sound" | tr -cd 'A-Za-z0-9 _-')
  if [ ! -f "/System/Library/Sounds/$sound.aiff" ]; then
    # A mistyped name must not silence the bell.
    sound_note="; no sound named '$sound', played $default_sound"
    sound="$default_sound"
  fi
fi

# VS Code writes paths into its state file as URIs, percent-encoded segment by segment.
file_uri() { jq -rn --arg p "$1" '"file://" + ($p | split("/") | map(@uri) | join("/"))'; }
shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
is_uuid() { [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }

# The first folder of a .code-workspace file, as an absolute path. The file is JSON that may
# carry comments: whole-line comments are dropped before jq reads it. Only when jq still
# cannot parse it is a pattern used instead, and that looks at the first folder alone.
workspace_first_folder() {
  local ws="$1" first
  if ! first=$(sed -E '/^[[:space:]]*\/\//d' "$ws" 2>/dev/null | jq -r '.folders[0].path // empty' 2>/dev/null); then
    first=$(sed -E '/^[[:space:]]*\/\//d' "$ws" 2>/dev/null | tr '\n' ' ' \
            | grep -o '"folders"[[:space:]]*:[[:space:]]*\[[[:space:]]*{[^}]*"path"[[:space:]]*:[[:space:]]*"[^"]*"' \
            | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')
  fi
  [ -n "$first" ] || return 0
  case "$first" in /*) ;; *) first="$(dirname "$ws")/$first" ;; esac
  (cd "$first" 2>/dev/null && pwd)
}

# VS Code brings an existing window forward only when asked to open exactly what that window
# holds: a folder, or a .code-workspace file. So the target is something VS Code lists among
# its open windows: a workspace inside the project folder or next to it whose first folder is
# the project directory (the extension starts a session in the first folder of a workspace),
# or else the project folder itself. Anything VS Code does not list is never a target: asking
# for it would open a new window, and a workspace file is not to be opened just because a
# repository ships one. Prints nothing when no window can be identified.
window_target() {
  local dir ws open_list
  dir=$(cd "$1" 2>/dev/null && pwd) || return 0
  open_list=$(jq -r '.windowsState | [.lastActiveWindow, (.openedWindows // [])[]] | .[]
                     | (.workspaceIdentifier.configURIPath // .folder // empty)' \
                "$VSCODE_STATE" 2>/dev/null)
  [ -n "$open_list" ] || return 0
  for ws in "$dir"/*.code-workspace "$(dirname "$dir")"/*.code-workspace; do
    [ -f "$ws" ] || continue
    grep -qxF "$(file_uri "$ws")" <<<"$open_list" || continue
    [ "$(workspace_first_folder "$ws")" = "$dir" ] || continue
    printf '%s' "$ws"
    return 0
  done
  if grep -qxF "$(file_uri "$dir")" <<<"$open_list"; then
    printf '%s' "$dir"
  fi
}

title="Claude · $project"
body=$(printf '%s' "$body" | tr '\n\t' '  ' \
       | sed -E 's/[*`#]+//g; s/ +/ /g; s/^[^[:alnum:]]+//' | cut -c1-140)
[ -n "$body" ] || body="$T_OPEN"

# Click-through is built for VS Code itself. Its forks report the same entry point but keep
# their state elsewhere and answer to another bundle id, so there the banner stays plain.
click=""; click_kind="none"
if [ "$entrypoint" = "claude-vscode" ]; then
  case "${VSCODE_CODE_CACHE_PATH:-/Application Support/Code/}" in
    *"/Application Support/Code/"*)
      click_kind="app"
      target=$(window_target "$project_dir")
      if [ -n "$target" ]; then
        click="/usr/bin/open -b $VSCODE_BUNDLE $(shell_quote "$target")"; click_kind="window"
        # The extension's own link then brings up this session's chat. VS Code hands such a
        # link to whichever window has focus, hence the pause after the window switch. The
        # link is left out when no window is known, because in a wrong window it starts a
        # blank chat, and when the id is not a session id.
        if is_uuid "$session"; then
          click="$click && sleep $FOCUS_PAUSE && /usr/bin/open -b $VSCODE_BUNDLE 'vscode://anthropic.claude-code/open?session=$session'"
          click_kind="chat"
        fi
      fi ;;
  esac
fi

# Test seam: record what would be shown instead of showing it.
if [ -n "${DOORBELL_DRY_RUN:-}" ]; then
  printf '%s\n' "title=$title" "subtitle=$subtitle" "body=$body" "sound=$sound" \
    "click_kind=$click_kind" "click=$click" >"$DATA_DIR/dry-run.txt"
  log "dry run: $kind$turn_note$sound_note"; exit 0
fi

# afplay bypasses Focus modes, which would silence a sound attached to the banner itself.
[ -n "$sound" ] && afplay "/System/Library/Sounds/$sound.aiff" 2>/dev/null &

via="none"; notifier_note=""
if [ -n "$NOTIFIER" ]; then
  args=(-title "$title" -subtitle "$subtitle" -message "$body" -group "doorbell-$session")
  case "$click_kind" in
    chat|window) args+=(-execute "$click") ;;
    app)         args+=(-activate "$VSCODE_BUNDLE") ;;
  esac
  if "$NOTIFIER" "${args[@]}" 2>/dev/null; then
    via="terminal-notifier"
  else
    notifier_note=" (terminal-notifier failed with exit $?)"   # 3 = not allowed to notify
  fi
fi
if [ "$via" = "none" ]; then
  # Fallback needs no setup, but its banner cannot be clicked through to the window.
  click_kind="none"
  osascript -e 'on run argv' \
    -e 'display notification (item 3 of argv) with title (item 1 of argv) subtitle (item 2 of argv)' \
    -e 'end run' "$title" "$subtitle" "$body" 2>/dev/null && via="osascript"
fi

quiet=""; [ -n "$sound" ] || quiet=" (no sound)"
log "alerted: $kind$quiet$turn_note, banner via $via$notifier_note, click: $click_kind$sound_note"

if is_on "$SPEAK" && [ -n "$spoken" ]; then
  wait   # let the sound finish before speaking over it
  phrase="$(printf '%s' "$project" | tr '_-' '  '): $spoken"
  if [ -z "$VOICE" ] || ! say -v "$VOICE" "$phrase" 2>/dev/null; then
    say "$phrase" 2>/dev/null   # the system voice, also when the chosen one is not installed
  fi
fi
wait
exit 0
