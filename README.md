# Caffeine

Keep your Mac awake while you work, or while your coding agents work without you.

Caffeine keeps the old cup and the one-click toggle. A full cup means the Mac stays awake. An empty cup means macOS can sleep normally. Right-click the cup for timers and settings. Option-click opens the full control panel.

Agent Watch adds a small blue dot to the bottom-right of the full cup while an agent is holding the session. A manual session uses the classic full cup on its own.

The menu-bar and app-icon artwork is the original MIT-licensed Caffeine artwork. It is kept intact rather than redrawn. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## What it does

- One click turns an indefinite awake session on or off.
- Agent Watch can install optional lifecycle hooks for Claude Code and Codex. It keeps the Mac awake during a turn, then releases the assertion when the agent finishes or waits for input.
- An optional process fallback supports Codex, Claude Code, OpenCode, Aider, Amp, Gemini CLI, Cursor Agent, and Goose. It stays active until the last matching process exits, so it is off by default.
- Timers cover 30 minutes, 1 hour, 2 hours, 8 hours, or any duration through the CLI.
- An active cup keeps the display on, matching classic Caffeine. You can allow display sleep in Power settings for unattended runs.
- Battery protection pauses assertions at a configurable charge level and resumes when power is safe.
- Closed-lid mode requests macOS's stronger system-sleep assertion.
- Other sleep blockers shows which apps and processes are also keeping the Mac, display, or network awake.
- A bundled `caffeine` command lets agents and scripts control the app directly.
- Launch at Login and signed Sparkle updates use the same setup as the other native apps in this folder.

## Closed-lid mode has a macOS limit

An ordinary app cannot override every lid policy on every Mac. Caffeine requests `PreventSystemSleep`, which is the strongest public best-effort assertion used here. macOS can still require power, an external display, and an external keyboard or mouse for reliable clamshell operation.

This app does not install a privileged helper, change `pmset`, or fake input. Those approaches are brittle and can leave the machine in a bad power state. The panel shows when closed-lid mode is requested, but it does not claim the hardware accepted it.

## Use the CLI

Install it from Settings > Command Line. It is copied to `~/.local/bin/caffeine`.

```sh
caffeine status --json
caffeine on
caffeine for 2h
caffeine off
```

Commands update the same persistent state as the app. A running app picks them up within one second.

## Build it

Caffeine is a SwiftPM macOS menu bar app. There is no Xcode project. It requires macOS 14 or newer.

```sh
swift build
make check
make dev
make install
```

`make dev` builds an ad-hoc signed app bundle, launches it through LaunchServices, and confirms that it stays running. `make install` installs the app to `/Applications` and the CLI to `~/.local/bin`.

## Check power behaviour

The live checks confirm that macOS accepted Caffeine's assertions. The guided tests record a heartbeat while the screen is off or the lid is closed.

```sh
make power-check
make power-test-screen
make power-test-lid
```

The lid test needs closed-lid mode turned on first. Add `CAFFEINE_TEST_URL=https://example.com` to either guided test to measure network continuity too. Results and raw samples go in `.build/power-tests/`. The [power testing guide](docs/power-testing.md) explains how to run each test and read the result.

## Ship it

`app.config.json` holds the public app identity. `version.env` holds the version and build number. Signing credentials stay outside the repo.

Set the same release environment variables used by Scheduler, then run `make release`.

```sh
export APP_IDENTITY="Developer ID Application: Name (TEAMID)"
export ASC_KEY_ID="KEYID"
export ASC_ISSUER_ID="ISSUERID"
export ASC_KEY_PATH="$HOME/.config/macos/AuthKey_KEYID.p8"
make release
```

Add the Sparkle public key to `app.config.json` before the first public release. Development builds leave updates disabled, so they never show a broken update prompt.

## Where data goes

Preferences and the last reported status stay in the `com.iannuttall.caffeine.shared` user defaults suite. If you install lifecycle hooks, Caffeine adds its own marked command handlers to `~/.claude/settings.json` and `~/.codex/hooks.json`. Existing hooks and unrelated settings are preserved, and removal only removes Caffeine's handlers. Active turns are recorded as small local marker files under `~/Library/Application Support/Caffeine/AgentSessions`.

The optional process fallback reads `/bin/ps` every eight seconds. Caffeine does not send process details, prompts, hook payloads, or usage data anywhere.

## License

MIT. See [LICENSE](LICENSE).
