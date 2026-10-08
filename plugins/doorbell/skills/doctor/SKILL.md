---
name: doctor
description: Check that Doorbell can deliver alerts on this Mac (notification permission, terminal-notifier, sounds) and send a test alert. Use when the user says Doorbell alerts do not show, do not sound or cannot be clicked, or asks to test or set up Doorbell.
---

Run this command and show the user its output unchanged:

```bash
CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"
```

Then say, in one or two sentences, what the user should do about each line marked `FAIL` or
`WARN`. If the output says macOS should now ask for permission to show notifications, tell
the user to allow it and to run the check again. Do not change any setting yourself.
