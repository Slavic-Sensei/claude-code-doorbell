# Changelog

## 0.1.1 — 2026-10-08

### Changed

- The options form says what the time limit measures and what an empty field means.
- The log gives the length of a finished turn and the limit in use.

## 0.1.0 — 2026-10-08

First release.

### Added

- A sound and a macOS banner when a Claude Code session in VS Code needs approval, asks a
  question, presents a plan, finishes a turn, or is stopped by an API error.
- A click on the banner that brings the VS Code window of the project forward and opens
  the chat of the session.
- One ring per prompt, a silent banner for a turn that ends with background work still
  running, and silence for turns shorter than 10 seconds and for headless runs.
- Options for the banner language (`en`, `cs`), the three sounds, a spoken project name,
  the time limit for short turns, and mute.
- A setup check, `/doorbell:doctor`, that sends a test alert.
