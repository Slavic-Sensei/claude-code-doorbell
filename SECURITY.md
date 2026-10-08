# Security

## Report a vulnerability

Please report a security problem privately: on the repository page, open the **Security**
tab and choose **Report a vulnerability**. Do not open a public issue for it.

Only the latest version receives fixes.

## What Doorbell does on your Mac

Doorbell is two shell scripts.

**`notify.sh`** is the one Claude Code runs as a hook. It:

- reads the event that Claude Code hands it, the list of open windows that VS Code keeps
  in `~/Library/Application Support/Code/User/globalStorage/storage.json`, and the
  `.code-workspace` files in the project folder and its parent folder;
- plays a system sound with `afplay`, shows a banner with terminal-notifier (or with
  `osascript` when terminal-notifier is missing or refused) and, with the `speak` option
  on, speaks with `say`. A click on the banner runs `/usr/bin/open` on a VS Code folder or
  workspace and on the extension's link to the chat;
- writes a log and a few small state files to
  `~/.claude/plugins/data/doorbell-slavic-sensei/`, trims the log, and deletes its own
  state files once they have not changed for three days.

**`doctor.sh`** runs only through the doctor skill: when you type `/doorbell:doctor`, or
when you ask Claude to check or test Doorbell. It reads the settings of terminal-notifier
and sends one test alert through `notify.sh`. If macOS has never been asked whether
terminal-notifier may show notifications, it also registers the terminal-notifier app with
macOS and opens it once, so that macOS shows its permission dialog.

Neither script makes a network request. The only permission they need is the macOS consent
to show notifications: for terminal-notifier, or for Script Editor when Doorbell falls back
to AppleScript.

## Untrusted input

Part of what the scripts read comes from the project you have open: its directory name,
the names and contents of `.code-workspace` files, and text written by the model or by an
MCP server. The scripts treat all of it as data:

- **The click command** of a banner is built only from a quoted path and from the session
  id, which is used only when it has the shape of a session id. A directory or file name
  cannot add a command to it.
- **A click asks VS Code only for what it already had open** when the alert was sent. A
  workspace file that sits in a repository is never opened just because it is there.
- **The log** holds the names of events, tools, MCP servers and projects, with control
  characters removed. It holds no message text and no commands.
- **A banner** never shows the shell command of a permission prompt, only the tool name and
  its description or file name.

The tests in [tests/run.sh](tests/run.sh) cover each of these points.
