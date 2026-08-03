<div align="center">

<img src="docs/assets/caffeine.svg" width="128" alt="Caffeine">

# Caffeine

**Keep your Mac awake while you work, then let it sleep when your coding agent waits for you.**

[Releases](https://github.com/iannuttall/caffeine/releases) ·
[Report a problem](https://github.com/iannuttall/caffeine/issues) · MIT licensed

</div>

---

## What Caffeine does

Caffeine keeps the cup and one-click toggle that made the original Mac app so good. Click it
once to keep your Mac awake. Click again and macOS can sleep normally. A full cup means a manual
session is active.

Agent Watch adds a small blue dot when a coding agent owns the awake session. Optional hooks
for Claude Code and Codex follow the actual turn. Caffeine turns on when work starts and releases
its power assertions when the agent finishes or waits for your input.

The app also includes timers, battery protection, display sleep controls, a best-effort
closed-lid mode, and a view of other processes currently blocking sleep.

## Credit to the original Caffeine

Tomas Franzén of Lighthead Software created Caffeine in 2006. Michael Jones and IntelliScape
Computer Solutions carried it forward from 2018 after Tomas released the source under an open
source license. The open source project was modernized again in 2022. The
[official Caffeine FAQ](https://www.caffeine-app.net/en/) tells the full story.

This project is an independent Swift rewrite. It keeps the original interaction and
MIT-licensed menu-bar artwork, then adds Agent Watch for coding agents.

## Install Caffeine

Caffeine supports Apple silicon and Intel Macs running macOS 14 or later.

Download the latest DMG from [GitHub Releases](https://github.com/iannuttall/caffeine/releases),
open it, and drag Caffeine to Applications. The app does not need administrator access or a
privileged helper. Launch at Login is optional and can be changed in Settings.

## Agent Watch follows active turns

Open Settings > Agents and install the optional lifecycle hooks. Caffeine adds its own marked
handlers to `~/.claude/settings.json` and `~/.codex/hooks.json`. Existing hooks and unrelated
settings are preserved. Removing the integration only removes handlers owned by Caffeine.

Restart Claude Code and Codex after installation. Codex asks you to review command hooks before
running them. Open `/hooks` and trust the Caffeine commands.

Process watching is available as a separate fallback for Claude Code, Codex, OpenCode, Aider,
Amp, Gemini CLI, Cursor Agent, and Goose. It keeps Caffeine active for as long as a matching app
or command is open, so it is off by default.

## Manual controls stay fast

- Left-click the cup to toggle an indefinite session.
- Right-click for timers and quick settings.
- Option-click to open the full control panel.
- Choose 30 minutes, 1 hour, 2 hours, 8 hours, or a custom CLI duration.

A setting can make left-click open the panel instead. Right-click and Option-click keep their
original jobs.

## Choose what stays awake

An active session prevents idle system sleep and display sleep, matching the original Caffeine.
Power settings can allow the display to turn off while the Mac and network stay awake.

Closed-lid mode requests macOS's stronger `PreventSystemSleep` assertion. macOS and the hardware
still decide whether clamshell operation is allowed. Caffeine does not change `pmset`, fake user
input, or promise that every Mac can work with its lid closed.

Battery protection pauses a requested session at the configured charge level. The session
resumes when external power returns or the battery recovers.

## Control it from the command line

Install the bundled command from Settings > Command Line. It is copied to
`~/.local/bin/caffeine`.

```sh
caffeine status --json
caffeine on
caffeine for 2h
caffeine off
```

Commands update the same persistent state as the app. A running app picks them up within one
second.

## Verify a downloaded build

Public builds are signed with Developer ID and notarized by Apple.

```sh
codesign --verify --deep --strict --verbose=2 /Applications/Caffeine.app
spctl --assess --type execute --verbose=4 /Applications/Caffeine.app
```

Each release includes a SHA-256 checksum beside its DMG. Download both files and check them with
this command.

```sh
cd ~/Downloads
shasum -a 256 -c Caffeine-*.dmg.sha256
```

## Build it locally

Caffeine is a Swift 6.2 SwiftPM app. There is no Xcode project.

```sh
swift build
make check
make dev
make package
```

`make dev` builds an ad-hoc signed app bundle, launches it, and confirms that it stays running.
`make package` builds the universal release bundle without using private signing credentials.

These are the main source areas.

```text
Sources/CaffeineCore/  portable policy, hook configuration, and parsers
Sources/Caffeine/      AppKit and SwiftUI app, services, settings, and menu bar UI
Sources/caffeinecli/   bundled command-line tool and lifecycle hook endpoint
Tests/                 pure Swift regression tests
Scripts/               build, signing, notarization, and power checks
```

Read [AGENTS.md](AGENTS.md) before changing the app. It records the behavior and macOS traps that
are easy to reintroduce. The [release guide](docs/releasing.md) covers signing and publishing.

## Check real power behavior

Unit tests cover the assertion policy. These commands check what macOS accepted from a running
build:

```sh
make power-check
make power-test-screen
make power-test-lid
```

The screen and lid tests deliberately change hardware state and save their evidence under
`.build/power-tests/`. The [power testing guide](docs/power-testing.md) explains the setup and
limits.

## Where data goes

Preferences and the last reported status stay in the `com.iannuttall.caffeine.shared` user
defaults suite. Active hook sessions use small marker files under
`~/Library/Application Support/Caffeine/AgentSessions`.

The optional process fallback reads `/bin/ps` every eight seconds while enabled. Caffeine does
not send prompts, process details, hook payloads, or usage data anywhere.

## Report bugs and request features

Open a [GitHub issue](https://github.com/iannuttall/caffeine/issues) with your macOS version,
which agent was running, and whether Agent Watch used hooks or process watching. Include the
output of `caffeine status --json` when it helps, but remove anything you do not want to share.

## License

Caffeine is MIT licensed. The upstream Caffeine menu-bar artwork keeps its MIT attribution
in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
