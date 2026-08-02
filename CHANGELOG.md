# Changelog

## 0.1.0 - 2026-08-01

- Rebuilt Caffeine as a Swift 6.2 SwiftPM menu bar app.
- Kept the original MIT-licensed empty and full cup artwork with one-click toggling.
- Added Agent Watch for common coding-agent processes.
- Added optional turn-aware lifecycle hooks for Claude Code and Codex, with safe merging that preserves existing hooks.
- Made process-based Agent Watch a separate, default-off fallback for keeping awake while an agent process remains open.
- Fixed Claude desktop processes being mistaken for active Claude Code sessions when macOS truncates the command path.
- Added manual timers, battery protection, display-sleep control, network assertions, and best-effort closed-lid mode.
- Added a shared command-line interface for scripts and agents.
- Added config-driven app packaging, Developer ID signing, notarization, Sparkle support, formatting, linting, tests, and CI.
- Added live process ownership for other macOS sleep assertions, including assertions created on behalf of another app.
- Added guided screen-off and lid-closed power tests with heartbeat, network, and competing-assertion evidence.
