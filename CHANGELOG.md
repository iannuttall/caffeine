# Changelog

## 0.1.1 - 2026-08-13

- Fixed launch crash when SwiftPM resource bundle could not be found in packaged app. (Thanks to @Jawher22 for reporting!)

## 0.1.0 - 2026-08-01

- Rebuilt Caffeine as a Swift 6.2 SwiftPM menu bar app.
- Kept the original MIT-licensed empty and full cup artwork with one-click toggling.
- Added Agent Watch for common coding-agent processes.
- Added optional turn-aware lifecycle hooks for Claude Code and Codex, with safe merging that preserves existing hooks.
- Matched Codex's three-second `SessionEnd` timeout cap to avoid configuration warnings.
- Made process-based Agent Watch a separate, default-off fallback for keeping awake while an agent process remains open.
- Fixed Claude desktop processes being mistaken for active Claude Code sessions when macOS truncates the command path.
- Added manual timers, battery protection, display-sleep control, network assertions, and best-effort closed-lid mode.
- Added a shared command-line interface for scripts and agents.
- Added config-driven app packaging, Developer ID signing, notarization, Sparkle support, formatting, linting, tests, and CI.
- Added a signed DMG release artifact, SHA-256 checksum, and bundle launch verification in CI and release builds.
- Added the custom Caffeine logo and app icon.
- Added live process ownership for other macOS sleep assertions, including assertions created on behalf of another app.
- Added guided screen-off and lid-closed power tests with heartbeat, network, and competing-assertion evidence.
- Fixed automatic launch at login failing silently when macOS initially reports the app service as missing.
