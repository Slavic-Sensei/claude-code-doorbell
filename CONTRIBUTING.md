# Contributing

Bug reports, fixes and translations are welcome.

## Scope

Doorbell does one thing: it tells you, on a Mac, that a Claude Code session in VS Code
needs you or has finished. Changes that make this more reliable are in scope. Support for
other systems or editors is out of scope for now. If you need it, open an issue to discuss
it before writing code.

## Report a bug

Open an issue with the **Bug report** form and include:

- the output of `/doorbell:doctor`,
- the lines of `~/.claude/plugins/data/doorbell-slavic-sensei/doorbell.log` from the time
  of the problem (the log holds no message text and no commands),
- your versions of macOS and chip (Apple Silicon or Intel), VS Code, the Claude Code
  extension, terminal-notifier and Doorbell.

For a security problem, see [SECURITY.md](SECURITY.md) instead.

## Work on the code

```bash
git clone https://github.com/Slavic-Sensei/claude-code-doorbell
cd claude-code-doorbell
bash tests/run.sh                                        # no sound, no banner
brew install shellcheck                                  # once
shellcheck plugins/doorbell/scripts/*.sh tests/run.sh
claude plugin validate --strict .                        # not part of CI
```

The tests replace the macOS tools with stand-ins that only record how they were called, so
they are safe to run on any Mac, including one where Doorbell is installed.

To try your working copy in VS Code, install the plugin from the folder instead of from
GitHub:

```bash
claude plugin marketplace add "$PWD"
claude plugin install doorbell@slavic-sensei
```

The plugin is then loaded in place. After an edit, type `/reload-plugins` in the chat.

## Rules for a change

- **A hook must never disturb a session.** Nothing on stdout or stderr, exit code 0 on
  every path.
- **Plain macOS.** The scripts run with `/bin/bash` 3.2 and the BSD tools that ship with
  macOS. `jq` is the only other dependency.
- **No message text and no commands in the log.** Names of events, tools and projects only.
- **Nothing is opened on a guess.** A click may only ask VS Code for what it already has
  open.
- **When in doubt, ring.** A second ring is better than a missed one.
- **A test for every change in behavior.** `tests/run.sh` has a case for each of the
  behavior rules above.
- **Comments explain why**, not what.

## Add a language

1. In [notify.sh](plugins/doorbell/scripts/notify.sh), copy one block of strings in the
   `case "$LANGUAGE"` statement and translate it.
2. Add the language code to the description of `language` in
   [plugin.json](plugins/doorbell/.claude-plugin/plugin.json) and to the options tables in
   the README and the guide.
3. Add a check to `tests/run.sh`, next to the one for `cs`.

## Release

Bump `version` in `plugin.json`, describe the change in `CHANGELOG.md`, and tag the
commit. People who have the plugin installed stay on their version until the number
changes.
