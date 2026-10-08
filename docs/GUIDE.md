# Doorbell guide

From nothing installed to your first ring, and everything you can tune afterwards.

- Getting started
  - [Before you start](#before-you-start)
  - [Install terminal-notifier](#install-terminal-notifier)
  - [Install the plugin](#install-the-plugin)
  - [The first ring](#the-first-ring)
  - [Try it for real](#try-it-for-real)
- Reference
  - [What rings and what stays quiet](#what-rings-and-what-stays-quiet)
  - [Options](#options)
  - [How a click works](#how-a-click-works)
  - [The log](#the-log)
  - [Troubleshooting](#troubleshooting)
  - [How it works](#how-it-works)
  - [Update and uninstall](#update-and-uninstall)
  - [Questions and answers](#questions-and-answers)

## Before you start

You need:

- **A Mac.** Doorbell uses the sounds and notifications of macOS. It is tested on macOS 27
  on Apple Silicon.
- **VS Code with the Claude Code extension.** Doorbell is tested with VS Code 1.140 and
  extension version 2.1.292.
- **`jq`**, a small tool for reading JSON. Recent versions of macOS include it. Check that
  it is there:

  ```bash
  jq --version
  ```

  If the command is not found, install it with `brew install jq`.
- **[Homebrew](https://brew.sh)**, to install terminal-notifier in the next step, and `jq` if it
  is missing.

## Install terminal-notifier

macOS lets a script show a banner, but not a banner that does something when you click it.
terminal-notifier adds that:

```bash
brew install terminal-notifier
```

On an Intel Mac, Homebrew has no prebuilt package and builds terminal-notifier from
source, which needs Xcode.

You can skip this step. Doorbell then shows a plain banner through AppleScript: you still
hear the sound and see which project is calling, but a click on the banner does not take
you to the chat.

## Install the plugin

Pick one of three ways.

**In VS Code.** In a Claude Code chat, type `/plugins`. On the **Marketplaces** tab, enter
this source to add it:

```text
Slavic-Sensei/claude-code-doorbell
```

Then, on the **Plugins** tab, find **Doorbell** and click **Install**. When asked where to
install it, choose **Install for you**, so the bell works in every project. A form with
the options follows. You can leave every field as it is.

**With a link.** Paste this address into your browser. VS Code opens the same dialog with
Doorbell already selected:

```text
vscode://anthropic.claude-code/install-plugin?plugin=doorbell&marketplace=Slavic-Sensei/claude-code-doorbell
```

**From a terminal**, if you have the `claude` command-line tool (check with
`claude --version`). This installs Doorbell for you, in every project:

```bash
claude plugin marketplace add Slavic-Sensei/claude-code-doorbell
claude plugin install doorbell@slavic-sensei
```

### Load the plugin into open chats

A new chat loads the plugin on its own. A chat that was open before the install may not
have it yet. Type this in the chat:

```text
/reload-plugins
```

It prints a summary of what it loaded. Doorbell adds seven hooks to the count. If you are
not sure whether a chat has the plugin, run the command anyway. It does no harm.

## The first ring

In a Claude Code chat, type:

```text
/doorbell:doctor
```

Claude runs a short shell script and may ask you to approve the command first. If it does,
approve it: that prompt is already your first ring. When everything is in place, the
result looks like this:

```text
Doorbell check
  ok    jq found
  ok    sound Funk found
  ok    sound Glass found
  ok    sound Basso found
  ok    terminal-notifier found (version 3.1.0)
  ok    terminal-notifier may show notifications
  ok    banners stay on screen until dismissed
  ok    VS Code window list found (a click on a banner can pick the right window)

Sending a test alert with the default sound and English text (your options apply to real alerts)...
  ok    alerted: done, banner via terminal-notifier, click: window

Log: /Users/you/.claude/plugins/data/doorbell-slavic-sensei/doorbell.log
```

You should hear the Glass sound and see a banner titled with the name of your project. The
test banner belongs to no chat, so a click on it only brings the window forward.

**The first time, expect a warning.** macOS has never been asked whether terminal-notifier
may show notifications, so the check says:

```text
  WARN  macOS has not been asked yet whether terminal-notifier may show notifications.
  WARN  It should ask now: choose Allow, then run this check again.
```

A macOS dialog appears. Choose **Allow**, then run `/doorbell:doctor` once more. Until you
do, the test alert is sent through AppleScript, and the check adds a warning about that as
well.

**Two settings worth changing,** both in System Settings → Notifications →
terminal-notifier. The entry appears there after the first test alert.

- **Alert style: Persistent** (called Alerts on older versions of macOS). A banner then
  stays on screen until you click or dismiss it. With the default style it disappears
  after a few seconds, and you would have to find it in Notification Center.
- **Show previews: When Unlocked**, if you do not want the start of Claude's replies to
  appear on a locked screen.

If you use a Focus mode and want to see banners while it is on, add terminal-notifier to
the apps that Focus allows. The sound plays in any case.

## Try it for real

1. Ask Claude for something that takes 10 seconds or longer. For example: *Read the README
   and the main source files and summarize this project in five points.*
2. Switch to another window or another app.
3. When Claude finishes, you hear **Glass** and a banner appears:
   **Claude · your-project**, *Finished — waiting for you*, and the first words of the
   reply.
4. Click the banner. The VS Code window of that project comes forward and the chat opens.
   The first time, VS Code may ask whether the extension is allowed to open such links.
   Choose **Open**.

To hear the sound for a prompt, ask Claude for something that needs your approval. For example:
*Create a file called hello.txt with the text hi.* If your permission mode asks before
edits, you hear **Funk** when the prompt appears, and the banner says
*Needs your approval*.

## What rings and what stays quiet

| Event | Sound | Banner |
| --- | --- | --- |
| Claude asks for permission to use a tool | Funk | *Needs your approval* and the tool with its description or file |
| Claude asks you a question | Funk | *Has a question for you* and the question |
| Claude presents a plan for approval | Funk | *Plan ready for review* |
| An MCP server asks for input | Funk | *MCP server asks for input*, the server's name and what it asks |
| Claude finishes its turn | Glass | *Finished — waiting for you* and the first words of the reply |
| An API error stops the turn | Basso | *Stopped by an error* and the error |
| A turn ends while agents or workflows it started are still running | none | *Paused — background work is still running* |

**Paused is not finished.** Claude can start an agent or a workflow in the background and
end its turn while that work goes on. Nobody is needed yet, so Doorbell shows a banner but
does not ring. Like a finished turn, a paused turn shorter than `min_done_seconds` is
skipped without a banner. When the background work reports back and Claude finishes, the
bell rings.

Only agents and workflows pause a turn. A shell command left running in the background
does not: it may be a development server that never ends. Such a turn rings as finished,
and if the command ends later and Claude has something to say about it, that rings as
well.

Doorbell stays quiet on purpose in these cases. The log names most of them.

| Case | Why | In the log |
| --- | --- | --- |
| A finished turn takes less than 10 seconds | You have most likely not looked away yet | `skipped: turn took 4s (limit 10s)` |
| A second or third event arrives for one prompt | You have already been told | `skipped: duplicate` |
| Claude runs without a chat window (`claude -p`, SDK scripts, cron jobs) | Nobody is waiting at a window | `skipped: headless` |
| The `mute` option is on | You asked for silence | `muted: done` |
| You interrupt Claude yourself | Claude Code reports no finished turn | nothing |
| A subagent finishes inside a turn | Only the main session's turn counts | nothing |

Doorbell goes by the clock alone. It cannot tell which chat you are looking at, so a turn
of 10 seconds or longer rings even when its chat is in front of you. A prompt that needs
you always rings, wherever you are looking. And when in doubt, Doorbell rings. After you
interrupt Claude, or when background work never reports back, it cannot tell when the next
turn began, so that turn is announced even if it was short.

## Options

Change them in VS Code: type `/plugins` and click the gear icon on Doorbell's row. With
the `claude` command-line tool, repeat the install command with the option:

```bash
claude plugin install doorbell@slavic-sensei --config min_done_seconds=30
```

If a change does not seem to apply in an open chat, type `/reload-plugins` there.

The form shows a text field empty until you set it. An empty field means the default from
this table.

| Option | Default | Meaning |
| --- | --- | --- |
| `language` | `en` | Language of the banner text: `en` or `cs`. |
| `min_done_seconds` | `10` | Turns shorter than this many seconds are not announced. Counted from your prompt until Claude stops. `0` announces every turn. |
| `sound_attention` | `Funk` | Sound when a session needs you. A name from `/System/Library/Sounds`. |
| `sound_done` | `Glass` | Sound when a session has finished. |
| `sound_error` | `Basso` | Sound when a turn was stopped by an error. |
| `speak` | `false` | After the sound, a voice says which project is calling. |
| `voice` | system voice | A voice from `say -v '?'`. |
| `mute` | `false` | No sound and no banner. Events are still logged. |

**The time limit.** `min_done_seconds` decides which finished turns are announced. The
clock starts when you send a prompt and stops when Claude does; time spent waiting for
your approval counts. A turn shorter than the limit ends without a sound or a banner, so a
higher number means fewer rings and `0` announces every turn. Prompts that need you and
errors always ring, whatever the limit. For a turn it could time, the log names both
numbers: `turn took 4s (limit 10s)`.

**Sounds.** Any sound in `/System/Library/Sounds` works. Give its name without the
extension. To list them and listen to one:

```bash
ls /System/Library/Sounds
afplay /System/Library/Sounds/Hero.aiff
```

An empty field plays the default sound from the table. So does a misspelled name, and
Doorbell logs the mistake: a typing error must not silence the bell. No value turns a
single sound off. For silence there is only `mute`, which hides the banner as well.

**Speaking the project name.** With several windows open, `speak` tells you which one is
calling without looking at the screen: after the sound, a voice says, for example,
"web: finished". Choose the voice with `voice`. This command lists the installed voices:

```bash
say -v '?'
```

With `language` set to `cs`, Doorbell uses the voice Zuzana unless you choose another.

## How a click works

A click on a banner does two things, one second apart.

**First it brings the right window forward.** VS Code does this only when it is asked to
open exactly what a window already holds: a folder, or a `.code-workspace` file. Doorbell
therefore reads the list of open windows that VS Code keeps in its own state file and looks
for the session's project in it. It accepts either of these:

- A window opened on a `.code-workspace` file whose first folder is the project. The file
  may sit inside the project folder or next to it, in its parent folder. Doorbell relies
  on the extension starting a session in the first folder of a workspace.
- A window opened on the project folder itself.

**Then it opens the chat.** Doorbell opens the extension's own link to the session,
`vscode://anthropic.claude-code/open?session=…`. The extension shows that chat, whether it
lives in an editor tab or in the side bar. VS Code hands such a link to whichever window
has focus, which is why the window switch comes first and the link a second later.

When no open window matches, a click only brings VS Code forward, and the link to the chat
is left out: in a wrong window it would start a blank chat. Doorbell asks VS Code only for
a folder or workspace that was in the list when the alert was sent. A workspace file that
merely sits in a folder is never opened. If you have closed the window since, a click on
an old banner opens it again.

Each alert in the log ends with what a click will do:

| `click:` | Meaning |
| --- | --- |
| `chat` | The window comes forward, then the chat opens. |
| `window` | The window comes forward. There was no session to link to. |
| `app` | VS Code comes forward. No window could be identified. |
| `none` | A plain banner: no terminal-notifier, or not VS Code. |

## The log

Each alert, and each decision not to alert, is one line in this file:

```text
~/.claude/plugins/data/doorbell-slavic-sensei/doorbell.log
```

```text
2026-10-08 12:06:31  e4f288e1 PreToolUse        AskUserQuestion      web                      claude-vscode alerted: attention, banner via terminal-notifier, click: chat
2026-10-08 12:06:31  e4f288e1 PermissionRequest AskUserQuestion      web                      claude-vscode ignored: covered by PreToolUse
2026-10-08 12:06:37  e4f288e1 Notification      permission_prompt    web                      claude-vscode skipped: duplicate
2026-10-08 12:07:04  e4f288e1 Stop              -                    web                      claude-vscode alerted: done, turn took 41s (limit 10s), banner via terminal-notifier, click: chat
```

From left to right: the time, the first characters of the session id, the event, the tool
or the kind of notification or error, the project, where Claude Code runs, and what
Doorbell did. The log holds no message text and no commands. A prompt you send writes no
line. Once the log grows past 2,000 lines it trims itself to the last 1,000.

| Outcome | Meaning |
| --- | --- |
| `alerted: …` | A sound was played and a banner was sent. `banner via` says how: `terminal-notifier`, `osascript`, or `none` when no banner could be shown. For a finished turn that Doorbell could time, `turn took Ns (limit Ms)` gives the turn's length and the `min_done_seconds` this chat uses. |
| `alerted: paused (no sound)` | The turn ended with background work still running: a banner, no ring. |
| `skipped: turn took Ns (limit Ms)` | The turn took N seconds, less than the `min_done_seconds` of M that this chat uses. |
| `skipped: duplicate` | Another event of the same prompt had already rung. |
| `skipped: headless` | A run without a chat window. |
| `muted: …` | The `mute` option is on. |
| `ignored: …` | An event Doorbell does not act on, such as the idle reminder, or a permission request already announced as a question or a plan. |

## Troubleshooting

Run `/doorbell:doctor` first. Then look at the last lines of the log: they tell you whether
Doorbell heard about the event at all, and what it decided.

| Symptom | Cause and fix |
| --- | --- |
| Nothing happens and the log gets no new lines | The chat has not loaded the plugin. Type `/reload-plugins`. If the log does not exist at all, check that `jq --version` works. |
| The log says `alerted`, but there is no sound | The sound follows the system volume. Check that the Mac is not muted. |
| Sound, but no banner | A Focus mode hides banners, or notifications for terminal-notifier are off or set to the alert style None. Both are in System Settings → Notifications. |
| The banner disappears after a few seconds | Set its alert style to Persistent. |
| The log says `banner via osascript` | Doorbell fell back to a plain banner, because terminal-notifier is missing or macOS does not let it notify. Run `/doorbell:doctor`; it names the cause. Banners sent this way come from Script Editor, which needs its own permission in System Settings → Notifications. |
| The log says `banner via none` | Neither terminal-notifier nor AppleScript could show a banner. Run `/doorbell:doctor`. |
| A click brings VS Code forward, but not the right window (`click: app`) | The project is not open as a folder, or as the first folder of a workspace, in any VS Code window. |
| A click opens the window, but shows a blank chat | The window switch took longer than the one-second pause. [Open an issue](https://github.com/Slavic-Sensei/claude-code-doorbell/issues) and attach the log lines from that time. |
| No ring after a short answer | That is `min_done_seconds`. Set it to `0` to hear every turn. |
| A ring after a quick answer, or in spite of the limit you set | Read the turn's line in the log. `turn took Ns (limit Ms)` gives its length and the limit this chat uses, and a turn rings when N is M or more. If M is not the number you set, type `/reload-plugins` in that chat. A line without `turn took` means Doorbell did not see the turn begin, and then it rings. Approvals, questions and errors always ring. |
| Two rings for one prompt | It should not happen. Open an issue and attach the log lines from that time. |

## How it works

The hook script, [notify.sh](../plugins/doorbell/scripts/notify.sh), is wired to seven
[hook events](https://code.claude.com/docs/en/hooks) of Claude Code:

| Event | Role |
| --- | --- |
| `PermissionRequest` | A permission prompt is about to appear. Rings at once. |
| `PreToolUse` for `AskUserQuestion` and `ExitPlanMode` | A question or a plan is about to appear. Rings at once, with the question as text. |
| `Elicitation` | An MCP server asks for input. Rings at once. |
| `Notification` | The fallback. Claude Code sends it only after a prompt has waited about six seconds, so Doorbell treats it as an echo of a ring already given. It rings on its own when nothing rang before it, for example when a sandboxed command asks to reach the network. |
| `Stop` | The turn ended. Rings, unless the turn was short or background work is still running. |
| `StopFailure` | An API error ended the turn. Rings. |
| `UserPromptSubmit` | You send a prompt. Marks the start of the turn and removes the session's old banner. |

One question therefore produces three events, and one ring:

```text
0 s   PreToolUse        AskUserQuestion    →  rings
0 s   PermissionRequest AskUserQuestion    →  ignored: covered by PreToolUse
6 s   Notification      permission_prompt  →  skipped: duplicate
```

The rules it follows:

- **It does not disturb a session.** Claude Code does not wait for the hooks. They return
  nothing to it and always exit with code 0.
- **One ring per prompt.** An event of the same session that arrives within two seconds of
  a ring counts as the same prompt. So does a `Notification` that arrives within ten
  seconds of a ring. Hook processes that start in the same moment compete for a lock, and
  only the first one rings.
- **A turn is measured from the prompt that started it.** Claude Code raises its prompt
  event not only for a prompt you type. It also raises it for a message you type while
  Claude works, for background work reporting back and for a scheduled task. A message
  typed in the middle of a turn and a report from background work do not restart the
  clock.
- **The sound is separate from the banner.** It is played directly, so a Focus mode that
  hides the banner does not silence it.
- **Nothing is guessed.** A click asks VS Code only for what its own list of windows
  contains.

Doorbell tells a headless run and the VS Code extension apart by environment variables
that Claude Code sets. If an update of the extension changes them, the log shows it:
alerts end with `click: none`.

## Update and uninstall

To update, refresh the marketplace, then the plugin:

```bash
claude plugin marketplace update slavic-sensei
claude plugin update doorbell@slavic-sensei
```

Then type `/reload-plugins` in open chats, or start new ones.

To uninstall:

```bash
claude plugin uninstall doorbell@slavic-sensei
claude plugin marketplace remove slavic-sensei
```

These commands also remove the log, the state files and your saved options. In VS Code you
can use the trash icons in `/plugins` instead; there you are asked whether to keep the
data. terminal-notifier stays. If nothing else uses it, remove it with
`brew uninstall terminal-notifier`.

## Questions and answers

**Does it work in Cursor, VS Code Insiders, or in a terminal?**

None of these is tested. Expect the sound and a plain banner, without the click, and
please report what you see.

**Does it work over SSH, in WSL or in a Dev Container?**

No. The hooks run on the remote machine, which has no way to ring on your Mac.

**Do subagents ring?**

A permission prompt rings whoever raised it, a subagent included. A subagent that finishes
inside a turn does not ring. Agents and workflows that keep running after the turn ended
make the turn paused: you get a banner then, and the ring when all of it is done.

**I have two chats in one window. Which one rang?**

The banner's text tells you what it is about, and a click opens exactly that chat. Each
chat has its own banner, and a new prompt in a chat removes that chat's old banner.

**Why 10 seconds?**

After an answer that quick you have most likely not looked away yet. That is a guess from
the clock: Doorbell cannot see where you are looking. Change the limit with
`min_done_seconds`.

**Does it ring on every `/loop` iteration?**

On every iteration that takes longer than `min_done_seconds`, because each one is a turn
that finishes. Raise the option, or turn on `mute`, if that is too much.

**Does Doorbell read my code or send anything anywhere?**

No. It reads the event that Claude Code hands it, plays a sound and shows a banner. It
makes no network requests. See [Privacy and security](../README.md#privacy-and-security).

**Can it ring on my phone?**

No. Doorbell is for the Mac you are sitting at.
