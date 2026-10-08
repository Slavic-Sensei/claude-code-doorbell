#!/bin/bash
#
# Purpose: Exercise notify.sh with the payload of every hook event, and doctor.sh, without
#          making a sound or showing a banner.
# Inputs:  None. Runs on macOS (the scripts under test rely on BSD stat and date).
# Outputs: One line per check; exit code 1 when any check fails.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NOTIFY="$ROOT/plugins/doorbell/scripts/notify.sh"
DOCTOR="$ROOT/plugins/doorbell/scripts/doctor.sh"
WORK=$(mktemp -d)   # left for macOS to clean up, so a failed run can be inspected
SESSION="11111111-2222-3333-4444-555555555555"
CODE_CACHE="/Users/x/Library/Application Support/Code/CachedData/abc"

checks=0; failed=0; n=0
pass()  { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
flunk() { checks=$((checks + 1)); failed=$((failed + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }

# --- stand-ins for the macOS tools: they record how they were called and do nothing else ----

STUBS="$WORK/stubs"; mkdir -p "$STUBS" "$WORK/home"
cat >"$STUBS/stub" <<'EOF'
#!/bin/bash
name=$(basename "$0")
line="$name"; for arg in "$@"; do line="$line"$'\t'"$arg"; done
printf '%s\n' "$line" >>"${DOORBELL_CALLS:-/dev/null}"   # one write: stand-ins run at the same moment
case "$name" in
  terminal-notifier)
    case "${1:-}" in
      -version)  echo "terminal-notifier ${STUB_VERSION:-3.1.0}."; exit 0 ;;
      -diagnose) printf '  bundle path         /nonexistent/terminal-notifier.app\n\n'
                 printf '  authorization       %s\n' "${STUB_AUTH:-authorized}"
                 printf '  alert style         %s\n' "${STUB_STYLE:-alerts (stay until dismissed)}"
                 exit 0 ;;
    esac
    exit "${STUB_NOTIFIER_EXIT:-0}" ;;
  osascript) exit "${STUB_OSASCRIPT_EXIT:-0}" ;;
  say)       if [ "${1:-}" = "-v" ] && [ -n "${STUB_BAD_VOICE:-}" ]; then exit 1; fi ;;
esac
exit 0
EOF
chmod +x "$STUBS/stub"
for tool in terminal-notifier afplay osascript say open; do ln -s stub "$STUBS/$tool"; done

# --- fixture: projects and the window list VS Code would keep for them ---------------------

P="$WORK/projects"
mkdir -p "$P/alpha" "$P/beta" "$P/My Project" "$P/gamma" "$P/it's" "$P/my-proj" \
         "$P/umbrella/delta" "$P/umbrella/epsilon" "$P/zeta" "$P/eta" "$P/theta" "$P/iota" \
         "$P/kappa" "$P/lambda"
echo '{"folders": [{"path": "."}]}' >"$P/alpha/alpha.code-workspace"
echo '{"folders": [{"path": "."}]}' >"$P/umbrella/delta/delta.code-workspace"   # exists, but no window holds it
echo '{"folders": [{"name": "d", "path": "delta"}, {"path": "epsilon"}]}' >"$P/umbrella/umbrella.code-workspace"
echo '{"folders": [{"path": "."}], "settings": {}}' >"$P/zeta/shipped.code-workspace"   # as a cloned repo might ship
echo '{"folders": [{"path": "."}]}' >"$P/eta/shipped.code-workspace"
cat >"$P/theta/theta.code-workspace" <<'EOF'
{
  // "path": "/an/old/place",
  "settings": {"terminal.integrated.profiles.osx": {"zsh": {"path": "zsh"}}},
  "folders": [{"path": "."}]
}
EOF
cat >"$P/iota/iota.code-workspace" <<'EOF'
{
  "folders": [
    {"path": "."},
  ],
}
EOF
# jq cannot read this one (trailing commas), and its first folder is not the project.
cat >"$P/kappa/kappa.code-workspace" <<'EOF'
{
  "folders": [
    {"uri": "vscode-remote://ssh-remote+box/srv/app"},
    {"path": "."},
  ],
}
EOF
# Readable only as JSON: a comment line, and a path that is written with a JSON escape.
cat >"$P/lambda/lambda.code-workspace" <<'EOF'
{
  // the app
  "folders": [{"path": "..\/lambda"}]
}
EOF
STATE_FILE="$WORK/storage.json"
jq -n --arg p "$P" '{windowsState: {
    lastActiveWindow: {workspaceIdentifier: {id: "1", configURIPath: ("file://" + $p + "/alpha/alpha.code-workspace")}},
    openedWindows: ([
      {folder: ("file://" + $p + "/beta")},
      {folder: ("file://" + $p + "/My%20Project")},
      {folder: ("file://" + $p + "/it%27s")},
      {folder: ("file://" + $p + "/eta")}
    ] + [("umbrella/umbrella", "theta/theta", "iota/iota", "kappa/kappa", "lambda/lambda")
         | {workspaceIdentifier: {id: ., configURIPath: ("file://" + $p + "/" + . + ".code-workspace")}}])}}' >"$STATE_FILE"
PROJECT="$P/alpha"

# --- helpers -------------------------------------------------------------------------------

new_case() { n=$((n + 1)); DATA="$WORK/data-$n"; mkdir -p "$DATA"; }

# hook DRY PAYLOAD [VAR=value ...] — run the hook script in a clean environment, with the
# bash 3.2 that ships with macOS.
hook() {
  local dry="$1" payload="$2"; shift 2
  env -i PATH="$STUBS:$PATH" HOME="$WORK/home" CLAUDE_PLUGIN_DATA="$DATA" \
      CLAUDE_CODE_ENTRYPOINT=claude-vscode CLAUDE_PROJECT_DIR="$PROJECT" \
      VSCODE_CODE_CACHE_PATH="$CODE_CACHE" DOORBELL_VSCODE_STATE="$STATE_FILE" \
      DOORBELL_CALLS="$DATA/calls.tsv" DOORBELL_DRY_RUN="$dry" "$@" /bin/bash "$NOTIFY" <<<"$payload"
}
fire()    { local payload="$1"; shift; hook 1 "$payload" "$@"; }    # the alert is recorded, not sent
deliver() { local payload="$1"; shift; hook "" "$payload" "$@"; }   # the alert goes to the stand-ins
doctor()  {
  env -i PATH="$STUBS:$PATH" HOME="$WORK/home" CLAUDE_PLUGIN_DATA="$DATA" \
      DOORBELL_CALLS="$DATA/calls.tsv" "$@" /bin/bash "$DOCTOR"
}

last_log() { tail -n 1 "$DATA/doorbell.log" 2>/dev/null; }
dry()      { sed -n "s/^$1=//p" "$DATA/dry-run.txt" 2>/dev/null; }
age()      { touch -t "$(date -v-"$2"S '+%Y%m%d%H%M.%S')" "$1"; }   # make a file N seconds old
calls()    { grep -c "^$1	" "$DATA/calls.tsv" 2>/dev/null; }
state_of() { if [ -e "$1" ]; then echo present; else echo absent; fi; }
names_in() { local f out=""; for f in "$1"/*; do out="$out${f##*/} "; done; printf '%s' "$out"; }
# The value that follows FLAG in the first recorded call of TOOL.
arg_after() {
  awk -F'\t' -v tool="$1" -v flag="$2" \
    '$1 == tool { for (i = 2; i < NF; i++) if ($i == flag) { print $(i + 1); exit } }' "$DATA/calls.tsv" 2>/dev/null
}

expect_log() { local line; line=$(last_log); case "$line" in *"$2"*) pass "$1" ;; *) flunk "$1" "wanted '$2' in: $line" ;; esac; }
expect_eq()  { if [ "$2" = "$3" ]; then pass "$1"; else flunk "$1" "wanted '$3', got '$2'"; fi; }
expect_has() { case "$2" in *"$3"*) pass "$1" ;; *) flunk "$1" "wanted '$3' in: $2" ;; esac; }
expect_not() { case "$2" in *"$3"*) flunk "$1" "did not want '$3' in: $2" ;; *) pass "$1" ;; esac; }

stop()       { printf '{"hook_event_name":"Stop","session_id":"%s","last_assistant_message":%s}' "$SESSION" "${1:-\"Done.\"}"; }
# A turn that ends with tasks still running in the background, given as a JSON array.
stop_with()  { printf '{"hook_event_name":"Stop","session_id":"%s","last_assistant_message":"Started.","background_tasks":%s}' "$SESSION" "$1"; }
prompt()     { printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s"}' "$SESSION"; }
permission() { printf '{"hook_event_name":"PermissionRequest","session_id":"%s","tool_name":"%s","tool_input":{"command":"curl -H TOKEN=hunter2","description":"Run the tests"}}' "$SESSION" "$1"; }
notice()     { printf '{"hook_event_name":"Notification","session_id":"%s","notification_type":"%s","message":"Claude needs your permission"}' "$SESSION" "$1"; }
question()   { printf '{"hook_event_name":"PreToolUse","session_id":"%s","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which one?"}]}}' "$SESSION"; }

# --- the hook must never disturb a session -------------------------------------------------

echo "Output and exit code"
new_case
out=$(fire 'not json at all' 2>&1; echo "exit=$?")
expect_eq "garbage input: silent, exit 0" "$out" "exit=0"
expect_eq "  and no alert" "$(state_of "$DATA/dry-run.txt") $(state_of "$DATA/calls.tsv")" "absent absent"
out=$(deliver "$(stop)" 2>&1; echo "exit=$?")
expect_eq "a delivered alert: nothing on stdout or stderr, exit 0" "$out" "exit=0"
out=$(fire '{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash"}' 2>&1; echo "exit=$?")
expect_eq "an event of no interest: silent, exit 0" "$out" "exit=0"
new_case
: >"$DATA/doorbell.log"; chmod 444 "$DATA/doorbell.log"
out=$(fire "$(stop)" 2>&1; echo "exit=$?")
expect_eq "a log that cannot be written: still silent, still exit 0" "$out" "exit=0"

# --- when a finished turn is announced -----------------------------------------------------

echo "Finished turns"
new_case
fire "$(prompt)"; fire "$(stop)"
expect_log "a turn that ends within seconds stays silent" "skipped: turn took"
age "$DATA/state/$SESSION.start" 60; fire "$(stop)"
expect_log "a turn of a minute is announced" "dry run: done"
expect_eq  "  title names the project" "$(dry title)" "Claude · alpha"
expect_eq  "  subtitle" "$(dry subtitle)" "Finished — waiting for you"
expect_eq  "  sound" "$(dry sound)" "Glass"

new_case
fire "$(prompt)"; fire "$(stop)"; fire "$(prompt)"; fire "$(stop)"
expect_eq "each new turn starts its own clock" "$(grep -c 'skipped: turn took' "$DATA/doorbell.log")" "2"
new_case
fire "$(prompt)"; age "$DATA/state/$SESSION.start" 60; fire "$(stop)"
fire "$(prompt)"; fire "$(stop)"
expect_log "a short turn after a long one is measured from its own prompt" "skipped: turn took"
new_case
fire "$(prompt)"; age "$DATA/state/$SESSION.start" 60
fire "$(printf '{"hook_event_name":"StopFailure","session_id":"%s","error":"rate_limit"}' "$SESSION")"
fire "$(prompt)"; fire "$(stop)"
expect_log "an error ends a turn too, so the next one is measured afresh" "skipped: turn took"

new_case
fire "$(prompt)"; fire "$(stop)" CLAUDE_PLUGIN_OPTION_MIN_DONE_SECONDS=0
expect_log "min_done_seconds=0 announces every turn" "dry run: done"
new_case
fire "$(prompt)"; fire "$(stop)" CLAUDE_PLUGIN_OPTION_MIN_DONE_SECONDS=.5
expect_log "  a fraction below one counts as 0" "dry run: done"
new_case
fire "$(prompt)"; age "$DATA/state/$SESSION.start" 4
fire "$(stop)" CLAUDE_PLUGIN_OPTION_MIN_DONE_SECONDS=2.5
expect_log "  2.5 counts as 2" "dry run: done"
for bad in soon 0.x . 1.5abc 1.2.3; do
  new_case
  fire "$(prompt)"; age "$DATA/state/$SESSION.start" 4
  fire "$(stop)" CLAUDE_PLUGIN_OPTION_MIN_DONE_SECONDS="$bad"
  expect_log "  '$bad' is no number and falls back to 10" "skipped: turn took"
done

new_case
fire "$(stop)"
expect_log "a session with no recorded prompt is announced" "dry run: done"
new_case
fire "$(prompt)"; touch -t 203001010000 "$DATA/state/$SESSION.start"
fire "$(stop)"
expect_log "a turn start from the future (a clock set back) does not silence the turn" "dry run: done"
new_case
fire "$(notice agent_completed)"
expect_log "a finished background session is announced" "dry run: done"
new_case
fire "$(stop)"; age "$DATA/state/$SESSION.done.last" 8
fire "$(notice agent_completed)"
expect_log "  also when it finishes 8 s after a turn of the same session" "dry run: done"

# Claude Code raises UserPromptSubmit for more than typed prompts, and Stop for more than
# finished work. The end of long work must not pass for a short turn.
echo "Turns that are longer than they look"
new_case
fire "$(prompt)"; age "$DATA/state/$SESSION.start" 60
fire "$(prompt)"   # a message typed while Claude is still working
fire "$(stop)"
expect_log "a prompt in the middle of a turn does not restart its clock" "dry run: done"

new_case
fire "$(prompt)"; age "$DATA/state/$SESSION.start" 60
fire "$(stop_with '[{"type":"subagent","status":"running","agent_type":"general-purpose"}]')"
expect_log "a turn that leaves an agent running in the background is paused, not finished" "dry run: paused"
expect_eq  "  the banner says so" "$(dry subtitle)" "Paused — background work is still running"
expect_eq  "  and there is no sound" "$(dry sound)" ""
fire "$(prompt)"   # the agent reporting back, which Claude Code also raises as a prompt
expect_eq  "  its report clears the mark the pause left" "$(state_of "$DATA/state/$SESSION.waking")" "absent"
fire "$(stop)"
expect_log "when the agent reports back and the turn ends, that is announced" "dry run: done"

new_case
fire "$(prompt)"; age "$DATA/state/$SESSION.start" 60
fire "$(stop_with '[{"type":"workflow","status":"running","name":"review"}]')" CLAUDE_PLUGIN_OPTION_LANGUAGE=cs
expect_eq "a running workflow pauses a turn too (and the banner is translated)" "$(dry subtitle)" "Pozastaveno — na pozadí se ještě pracuje"
new_case
fire "$(prompt)"; age "$DATA/state/$SESSION.start" 4
fire "$(stop_with '[{"type":"subagent","status":"running"}]')"
expect_log "a short turn that leaves an agent running stays silent like any short turn" "skipped: turn took"
expect_eq  "  but it is remembered as paused" "$(state_of "$DATA/state/$SESSION.waking")" "present"

new_case
fire "$(prompt)"; age "$DATA/state/$SESSION.start" 60
fire "$(stop_with '[{"type":"shell","status":"running","command":"npm run dev"}]')"
expect_log "a shell command left running does not pause a turn: it may be a server" "dry run: done"
# What Claude Code sends when background work reports back is recognised by its notice too.
age "$DATA/state/$SESSION.done.last" 30
fire "$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","prompt":"<task-notification>\\n<task-id>abc</task-id>"}' "$SESSION")"
fire "$(stop)"
expect_log "  and when it reports back, what Claude then says is announced as well" "dry run: done"
new_case
fire "$(prompt)"; age "$DATA/state/$SESSION.start" 60
fire "$(stop_with '[{"type":"teammate","status":"running"}]')"
expect_log "nor does a teammate, which may idle for as long as its team lives" "dry run: done"

# --- one alert per prompt ------------------------------------------------------------------

echo "Prompts"
new_case
fire "$(permission Bash)"
expect_log "permission request alerts" "dry run: attention"
expect_eq  "  body is tool and description" "$(dry body)" "Bash: Run the tests"
expect_not "  the command never reaches the banner" "$(cat "$DATA/dry-run.txt")" "hunter2"
expect_not "  ...nor the log" "$(cat "$DATA/doorbell.log")" "hunter2"
age "$DATA/state/$SESSION.attention.last" 6; fire "$(notice permission_prompt)"
expect_log "its Notification echo 6 s later is dropped" "skipped: duplicate"
age "$DATA/state/$SESSION.attention.last" 12; fire "$(notice permission_prompt)"
expect_log "a Notification 12 s after the last ring is a prompt of its own" "dry run: attention"
age "$DATA/state/$SESSION.attention.last" 3; fire "$(permission Edit)"
expect_log "a new prompt 3 s later alerts again" "dry run: attention"
fire "$(permission Write)"
expect_log "a twin event in the same moment is dropped" "skipped: duplicate"

new_case
fire "$(notice permission_prompt)"
expect_log "a Notification nothing announced before alerts on its own" "dry run: attention"
new_case
fire "$(notice quota_auto_resume_stale)"
expect_log "a wait for a usage limit that ended without continuing alerts" "dry run: attention"
new_case
mkdir -p "$DATA/state"; : >"$DATA/state/$SESSION.attention.last"; touch -t 203001010000 "$DATA/state/$SESSION.attention.last"
fire "$(permission Bash)"
expect_log "a stamp from the future (a clock set back) does not silence a session" "dry run: attention"

new_case
fire "$(question)"
expect_log "question alerts" "dry run: attention"
expect_eq  "  body is the question" "$(dry body)" "Which one?"
fire "$(permission AskUserQuestion)"
expect_log "the question's PermissionRequest twin is ignored" "ignored: covered by PreToolUse"

new_case
fire "$(printf '{"hook_event_name":"PermissionRequest","session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"/repo/src/app.ts"}}' "$SESSION")"
expect_eq "a tool without a description shows its file" "$(dry body)" "Edit: /repo/src/app.ts"
new_case
fire "$(printf '{"hook_event_name":"Elicitation","session_id":"%s","mcp_server_name":"github","message":"Choose a repository"}' "$SESSION")"
expect_log "an MCP server asking for input alerts" "dry run: attention"
expect_eq  "  subtitle" "$(dry subtitle)" "MCP server asks for input"
expect_eq  "  body is the server and what it asks" "$(dry body)" "github: Choose a repository"

new_case
fire "$(notice idle_prompt)"
expect_log "idle_prompt is ignored" "ignored"
fire "$(printf '{"hook_event_name":"StopFailure","session_id":"%s","error":"rate_limit","last_assistant_message":"API Error: Rate limit reached"}' "$SESSION")"
expect_log "an API error alerts" "dry run: error"
expect_log "  the log names the kind of error" "rate_limit"
expect_eq  "  the banner shows the error text" "$(dry body)" "API Error: Rate limit reached"
expect_eq  "  sound" "$(dry sound)" "Basso"

# Hook processes of one session start together; however many there are, one may alert.
echo "Simultaneous events"
new_case
for _ in 1 2 3 4 5 6; do fire "$(permission Bash)" & done; wait
expect_eq "six at once, first alert of a session: one alerts" "$(grep -c 'dry run' "$DATA/doorbell.log")" "1"
# Without the mutex about half of such rounds ring twice, so ten rounds leave little to luck.
doubles=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  new_case
  mkdir -p "$DATA/state"; : >"$DATA/state/$SESSION.attention.last"; age "$DATA/state/$SESSION.attention.last" 60
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do fire "$(permission Bash)" & done; wait
  [ "$(grep -c 'dry run' "$DATA/doorbell.log")" = "1" ] || doubles=$((doubles + 1))
done
expect_eq "twelve at once after an earlier alert, ten rounds: one alerts every time" "$doubles" "0"

new_case
mkdir -p "$DATA/state/$SESSION.attention.last.mutex"; age "$DATA/state/$SESSION.attention.last.mutex" 60
fire "$(permission Bash)"
expect_log "a mutex left by a killed process does not block alerts" "dry run: attention"
expect_eq  "  it was cleared, taken and released" "$(state_of "$DATA/state/$SESSION.attention.last.mutex")" "absent"
new_case
mkdir -p "$DATA/state/$SESSION.attention.last.mutex"
fire "$(permission Bash)"
expect_log "a mutex that is never released delays the alert, it does not swallow it" "dry run: attention"
expect_eq  "  and a mutex held by another process is left alone" "$(state_of "$DATA/state/$SESSION.attention.last.mutex")" "present"

# --- who is not alerted --------------------------------------------------------------------

echo "Filters and options"
new_case
fire "$(stop)" CLAUDE_CODE_ENTRYPOINT=sdk-cli
expect_log "headless runs are skipped" "skipped: headless"
fire "$(stop)" CLAUDE_PLUGIN_OPTION_MUTE=true
expect_log "mute silences alerts" "muted: done"

new_case
fire "$(permission Bash)" CLAUDE_PLUGIN_OPTION_LANGUAGE=cs CLAUDE_PLUGIN_OPTION_SOUND_ATTENTION=Ping
expect_eq "language cs" "$(dry subtitle)" "Čeká na schválení"
expect_eq "custom sound" "$(dry sound)" "Ping"
new_case
fire "$(stop)" CLAUDE_PLUGIN_OPTION_LANGUAGE=xx CLAUDE_PLUGIN_OPTION_SOUND_DONE=../../tmp/Glas
expect_eq  "an unknown language falls back to English" "$(dry subtitle)" "Finished — waiting for you"
expect_eq  "a sound that does not exist falls back to the default" "$(dry sound)" "Glass"
expect_log "  and the log says so" "no sound named 'tmpGlas', played Glass"

new_case
# shellcheck disable=SC2016  # the backticks are part of the test message, not a command
fire "$(stop '"**Summary:** `tests` pass.\n\n- one\n- two"')"
expect_eq "markdown is flattened" "$(dry body)" "Summary: tests pass. - one - two"
new_case
fire "$(stop "\"$(printf 'x%.0s' $(seq 1 300))\"")"
expect_eq "long text is cut to 140 characters" "$(dry body | wc -m | tr -d ' ')" "141"
new_case
fire "$(printf '{"hook_event_name":"PreToolUse","session_id":"%s","tool_name":"ExitPlanMode"}' "$SESSION")"
expect_eq "a plan is announced as one" "$(dry subtitle)" "Plan ready for review"
expect_eq "  and an empty body gets a default text" "$(dry body)" "Open the chat to continue"

echo "The log and the state directory"
new_case
PROJECT="$WORK/line"$'\n'"FORGED 2026-01-01"
fire "$(stop)"
expect_eq "a directory name with a line break cannot forge a log line" "$(wc -l <"$DATA/doorbell.log" | tr -d ' ')" "1"
PROJECT="$P/alpha"
new_case
fire "$(printf '{"hook_event_name":"PermissionRequest","session_id":"%s","tool_name":"Bash\\nFORGED 2026-01-01 00:00:00  x  Stop\\u0007"}' "$SESSION")"
expect_eq  "nor can a tool name" "$(wc -l <"$DATA/doorbell.log" | tr -d ' ')" "1"
expect_not "  and no control character is left in the log" "$(cat -v "$DATA/doorbell.log")" "^G"
new_case
fire "$(printf '{"hook_event_name":"Elicitation","session_id":"%s","mcp_server_name":"srv\\nFORGED 2026-01-01","message":"x"}' "$SESSION")"
expect_eq  "nor can the name of an MCP server" "$(wc -l <"$DATA/doorbell.log" | tr -d ' ')" "1"
new_case
fire "$(printf '{"hook_event_name":"Stop","session_id":"%s-a","last_assistant_message":"SECRET-REPLY"}' "$SESSION")"
fire "$(printf '{"hook_event_name":"PreToolUse","session_id":"%s-b","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"SECRET-QUESTION"}]}}' "$SESSION")"
fire "$(printf '{"hook_event_name":"Elicitation","session_id":"%s-c","mcp_server_name":"srv","message":"SECRET-REQUEST"}' "$SESSION")"
fire "$(printf '{"hook_event_name":"Notification","session_id":"%s-d","notification_type":"permission_prompt","message":"SECRET-NOTICE"}' "$SESSION")"
fire "$(printf '{"hook_event_name":"StopFailure","session_id":"%s-e","error":"rate_limit","last_assistant_message":"SECRET-ERROR-TEXT"}' "$SESSION")"
expect_eq  "a reply, a question, an MCP request, a notice and an error text are announced" "$(grep -c 'dry run' "$DATA/doorbell.log")" "5"
expect_not "  and none of their text reaches the log" "$(cat "$DATA/doorbell.log")" "SECRET"
new_case
fire '{"hook_event_name":"UserPromptSubmit","session_id":"../../escape"}'
expect_eq "a session id cannot point outside the state directory" "$(names_in "$DATA/state")" "escape.start escape.working "
new_case
mkdir -p "$DATA/state"; seq 1 2100 >"$DATA/doorbell.log"; : >"$DATA/state/old.start"; age "$DATA/state/old.start" 300000
fire "$(prompt)"
expect_eq "a long log is cut back on the next prompt" "$(wc -l <"$DATA/doorbell.log" | tr -d ' ')" "1000"
expect_eq "  and state files left over from days ago are removed" "$(state_of "$DATA/state/old.start")" "absent"

# --- where a click on the banner leads -----------------------------------------------------

echo "Click-through"
target_of() { eval "set -- ${1%% && *}"; printf '%s' "$4"; }   # the path handed to `open`

new_case
fire "$(stop)"
expect_eq  "own workspace: click opens the chat" "$(dry click_kind)" "chat"
expect_eq  "  via the workspace file" "$(target_of "$(dry click)")" "$P/alpha/alpha.code-workspace"
expect_has "  then the session link" "$(dry click)" "vscode://anthropic.claude-code/open?session=$SESSION"

new_case; PROJECT="$P/beta"
fire "$(stop)"
expect_eq "folder window: target is the folder" "$(target_of "$(dry click)")" "$P/beta"

new_case; PROJECT="$P/My Project"
fire "$(stop)"
expect_eq "a path with a space is matched and quoted" "$(target_of "$(dry click)")" "$P/My Project"

new_case; PROJECT="$P/it's"
fire "$(stop)"
expect_eq "a path with a quote is matched and quoted" "$(target_of "$(dry click)")" "$P/it's"

new_case; PROJECT="$P/umbrella/delta"
fire "$(stop)"
expect_eq "of two matching workspaces only the open one is used" "$(target_of "$(dry click)")" "$P/umbrella/umbrella.code-workspace"

new_case; PROJECT="$P/theta"
fire "$(stop)"
expect_eq "a workspace with comments, and settings before folders" "$(target_of "$(dry click)")" "$P/theta/theta.code-workspace"
new_case; PROJECT="$P/lambda"
fire "$(stop)"
expect_eq "a commented workspace is read as JSON, escapes and all" "$(target_of "$(dry click)")" "$P/lambda/lambda.code-workspace"
new_case; PROJECT="$P/iota"
fire "$(stop)"
expect_eq "a workspace with trailing commas is still understood" "$(target_of "$(dry click)")" "$P/iota/iota.code-workspace"
new_case; PROJECT="$P/kappa"
fire "$(stop)"
expect_eq "  but only its first folder counts" "$(dry click_kind)" "app"

new_case; PROJECT="$P/zeta"
fire "$(stop)"
expect_eq "a workspace file no window holds is never opened" "$(grep -c '^click=$' "$DATA/dry-run.txt")" "1"
expect_eq "  the click only brings VS Code forward" "$(dry click_kind)" "app"
new_case; PROJECT="$P/eta"
fire "$(stop)"
expect_eq "  and it does not hide the folder window next to it" "$(target_of "$(dry click)")" "$P/eta"

new_case; PROJECT="$P/gamma"
fire "$(stop)"
expect_eq "unknown window: only bring VS Code forward" "$(dry click_kind)" "app"
expect_eq "  no command, so no stray window or chat" "$(grep -c '^click=$' "$DATA/dry-run.txt")" "1"

new_case; PROJECT="$P/alpha"
fire "$(stop)" DOORBELL_VSCODE_STATE="$WORK/missing.json"
expect_eq "no window list: only bring VS Code forward" "$(dry click_kind)" "app"
echo 'not json' >"$WORK/broken.json"
new_case
fire "$(stop)" DOORBELL_VSCODE_STATE="$WORK/broken.json"
expect_eq "a window list that cannot be read: the same" "$(dry click_kind)" "app"

new_case
fire '{"hook_event_name":"Stop","last_assistant_message":"Done."}'
expect_eq "no session id: window only" "$(dry click_kind)" "window"
new_case
fire '{"hook_event_name":"Stop","session_id":"doorbell-doctor","last_assistant_message":"Done."}'
expect_eq "an id that is no session id: window only" "$(dry click_kind)" "window"

new_case
fire "$(stop)" VSCODE_CODE_CACHE_PATH="/Users/x/Library/Application Support/Cursor/CachedData/abc"
expect_eq "another editor: plain banner" "$(dry click_kind)" "none"
new_case
fire "$(stop)" CLAUDE_CODE_ENTRYPOINT=cli
expect_eq "terminal session: plain banner" "$(dry click_kind)" "none"

# --- what is handed to the macOS tools -----------------------------------------------------

echo "Delivery"
new_case
deliver "$(stop)"
expect_log "an alert is delivered" "alerted: done, banner via terminal-notifier, click: chat"
expect_eq  "  the sound is played" "$(grep '^afplay' "$DATA/calls.tsv" | cut -f2)" "/System/Library/Sounds/Glass.aiff"
expect_eq  "  the banner carries the title" "$(arg_after terminal-notifier -title)" "Claude · alpha"
expect_eq  "  the subtitle" "$(arg_after terminal-notifier -subtitle)" "Finished — waiting for you"
expect_eq  "  the text" "$(arg_after terminal-notifier -message)" "Done."
expect_eq  "  one banner per session" "$(arg_after terminal-notifier -group)" "doorbell-$SESSION"
expect_eq  "  and the click command" "$(target_of "$(arg_after terminal-notifier -execute)")" "$P/alpha/alpha.code-workspace"

new_case
deliver "$(prompt)"
expect_eq "a new prompt clears the session's old banner" "$(arg_after terminal-notifier -remove)" "doorbell-$SESSION"

new_case
deliver "$(stop_with '[{"type":"subagent","status":"running"}]')"
expect_log "a paused turn gets a banner" "alerted: paused (no sound), banner via terminal-notifier, click: chat"
expect_eq  "  that says it is paused" "$(arg_after terminal-notifier -subtitle)" "Paused — background work is still running"
expect_eq  "  and no sound is played" "$(calls afplay)" "0"

new_case; PROJECT="$P/gamma"
deliver "$(stop)"
expect_eq "unknown window: the banner brings VS Code forward" "$(arg_after terminal-notifier -activate)" "com.microsoft.VSCode"
expect_eq "  and carries no command" "$(grep -c -e '-execute' "$DATA/calls.tsv")" "0"
PROJECT="$P/alpha"

new_case
deliver "$(stop)" STUB_NOTIFIER_EXIT=3
expect_log "when terminal-notifier may not notify, AppleScript shows the banner" "banner via osascript (terminal-notifier failed with exit 3), click: none"
expect_eq  "  with title, subtitle and text" "$(grep '^osascript' "$DATA/calls.tsv" | awk -F'\t' '{print $(NF-2) " | " $(NF-1) " | " $NF}')" "Claude · alpha | Finished — waiting for you | Done."
new_case
deliver "$(stop)" STUB_NOTIFIER_EXIT=3 STUB_OSASCRIPT_EXIT=1
expect_log "when neither can, the log says no banner was shown" "banner via none"

new_case; PROJECT="$P/my-proj"
deliver "$(stop)" CLAUDE_PLUGIN_OPTION_SPEAK=true
expect_eq "speak: the system voice says project and state" "$(grep '^say' "$DATA/calls.tsv")" "say	my proj: finished"
expect_eq "  after the sound" "$(cut -f1 "$DATA/calls.tsv" | grep -e afplay -e say | tr '\n' ' ')" "afplay say "
new_case
deliver "$(stop)" CLAUDE_PLUGIN_OPTION_SPEAK=true CLAUDE_PLUGIN_OPTION_LANGUAGE=cs
expect_eq "speak in Czech uses a Czech voice" "$(grep '^say' "$DATA/calls.tsv")" "say	-v	Zuzana	my proj: hotovo"
new_case
deliver "$(stop)" CLAUDE_PLUGIN_OPTION_SPEAK=true CLAUDE_PLUGIN_OPTION_VOICE=Nobody STUB_BAD_VOICE=1
expect_eq "a voice that is not installed falls back to the system voice" "$(grep -c '^say	my proj: finished$' "$DATA/calls.tsv")" "1"
new_case
deliver "$(stop)"
expect_eq "without speak nothing is said" "$(calls say)" "0"
new_case
deliver "$(stop_with '[{"type":"subagent","status":"running"}]')" CLAUDE_PLUGIN_OPTION_SPEAK=true
expect_eq "a paused turn is not spoken either" "$(calls say)" "0"
PROJECT="$P/alpha"

# --- the setup check -----------------------------------------------------------------------

echo "Doctor"
new_case
out=$(doctor; echo "exit=$?")
expect_has "all well: permission" "$out" "ok    terminal-notifier may show notifications"
expect_has "  alert style" "$out" "ok    banners stay on screen until dismissed"
expect_has "  the test alert" "$out" "ok    alerted: done, banner via terminal-notifier"
expect_has "  exit code 0" "$out" "exit=0"
new_case
out=$(doctor STUB_AUTH=denied; echo "exit=$?")
expect_has "notifications turned off: FAIL" "$out" "FAIL  Notifications for terminal-notifier are turned off."
expect_has "  exit code 1" "$out" "exit=1"
new_case
out=$(doctor STUB_AUTH="not requested yet"; echo "exit=$?")
expect_has "permission never asked: WARN" "$out" "WARN  macOS has not been asked yet"
new_case
out=$(doctor STUB_STYLE=none; echo "exit=$?")
expect_has "alert style None: WARN" "$out" "WARN  Its alert style is None"
new_case
out=$(doctor STUB_VERSION=2.0.0; echo "exit=$?")
expect_has "an old terminal-notifier: WARN" "$out" "WARN  Doorbell is tested with terminal-notifier 3"
new_case
out=$(doctor STUB_NOTIFIER_EXIT=3; echo "exit=$?")
expect_has "banner through AppleScript: said, with a caveat" "$out" "WARN  The banner was sent through Script Editor"

# -------------------------------------------------------------------------------------------

echo
if [ "$failed" -eq 0 ]; then
  echo "$checks checks passed"
else
  echo "$failed of $checks checks FAILED (state kept in $WORK)"
  exit 1
fi
