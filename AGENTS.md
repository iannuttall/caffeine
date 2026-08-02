# Repository guidelines

Caffeine is a native macOS menu bar app for keeping a Mac awake during manual sessions and coding-agent runs. It uses Swift 6.2, SwiftPM, AppKit for the status item and panel, SwiftUI for content, IOKit for power assertions, and Sparkle for direct updates. There is no Xcode project.

Read this file before changing anything. The traps below are product contracts or bugs that are easy to reintroduce.

## Project structure

- `Sources/CaffeineCore/` contains portable policy, duration, and process-list parsing logic. It must not import AppKit, SwiftUI, or IOKit.
- `Sources/caffeinecli/` contains the agent-facing CLI.
- `Sources/Caffeine/` contains the macOS app. Services own process and power APIs. UI owns the panel, status item, and settings.
- `Tests/CaffeineCoreTests/` uses Swift Testing for pure logic.
- `Scripts/` contains build, ad-hoc signing, install, Developer ID signing, and notarization tools.
- `app.config.json` is the source of truth for public app identity. `version.env` owns version numbers.

## Build, test, and run

- `make dev` builds an app bundle, ad-hoc signs it, launches it, and verifies the process stays alive.
- `make check` formats, lints, and runs tests. Run it after every source change.
- `swift test` runs the Swift Testing suite.
- `make package` builds a universal release bundle.
- `make release` signs, notarizes, staples, and creates the final zip. Do not run signing steps by hand.

## Code style

- Run SwiftFormat and SwiftLint through `make check`.
- Four-space indentation and explicit `self` are intentional.
- Use `@Observable`, `@State`, and `@Bindable`. Do not add Combine observation types.
- Core behavior needs a pure test. UI types should stay thin.
- Comments explain a power-management constraint or a UI trap, not the line underneath them.

## Product contracts and traps

**The classic click stays fast.** The default left click toggles Caffeine immediately. Right-click opens quick controls. Option-click opens the panel. A setting can change left click to open the panel, but do not remove the default muscle-memory path.

**The cup is a template image.** Set `isTemplate` on the final `NSImage` handed to the menu bar. Do not set `contentTintColor`. Both details are required for the icon to follow light and dark menu bars.

**Automatic mode has one small badge.** The original full cup alone means a manual session. A blue dot tucked into its bottom-right corner means Agent Watch owns the session. The badged image cannot be a template, so draw the original cup in `labelColor` inside a deferred image handler and leave `contentTintColor` nil. Clear `attributedTitle` in every state so stale text cannot widen the status item.

**Display sleep and system sleep are separate.** Active sessions default to both `PreventUserIdleSystemSleep` and `PreventUserIdleDisplaySleep`, matching classic Caffeine. The user can turn on display sleep for unattended runs.

**Closed-lid support is best effort.** The app adds `PreventSystemSleep`, but macOS and the hardware keep final control of lid behavior. Never promise guaranteed closed-lid work. Do not add `sudo pmset`, private APIs, fake input, or a privileged helper without an explicit product decision.

**Every assertion must be released.** `PowerAssertionManager` replaces the whole plan and releases every assertion when the session stops or the app exits. A partial assertion failure releases the assertions already created.

**Other sleep blockers are read-only.** Use `IOPMCopyAssertionsByProcess`, resolve on-behalf-of PIDs when possible, and hide Caffeine's own assertions plus powerd's normal display-on assertion. Do not offer a kill action for system power assertions.

**Agent Watch prefers lifecycle hooks.** Claude Code and Codex hooks create per-session activity markers while a turn is running and remove them when the agent finishes or waits for input. Hook installation must merge with existing JSON, preserve every handler it does not own, and removal must only delete commands carrying Caffeine's marker. A broken hook must never interrupt an agent.

**Process watching is an optional fallback.** Terminal agents are not normal `NSRunningApplication` instances. When enabled, the scanner uses `/bin/ps`, runs in an actor, and feeds a portable parser. Keep shell output parsing out of the UI and keep scans off the main actor. The fallback can include a main agent app process, but never its helper processes.

**A manual stop pauses active agents.** If Agent Watch is holding the session, clicking the cup pauses it until the detected agents exit. Otherwise the assertion would switch straight back on and the toggle would feel broken.

**Battery protection pauses rather than deletes.** A requested session resumes after the battery recovers or external power returns. The app must not silently discard a timer or manual session because the charge crossed the cutoff.

**The panel owns its size.** Do not use intrinsic hosting-view sizing. SwiftUI content changes once per second, and letting it resize the panel would move the panel away from the menu bar.

**Development builds do not run Sparkle.** The updater requires a real app bundle, feed URL, and public key. Debug packaging leaves the feed and key empty on purpose.

## Verification

After app changes run `make check`, then `make dev`. Confirm the exact bundle is running with:

```sh
pgrep -af "Caffeine.app/Contents/MacOS/Caffeine"
```

Use `CAFFEINE_OPEN_ON_LAUNCH=1 make dev` to open the control panel during launch checks. Use the built CLI to check shared state:

```sh
.build/package/Caffeine.app/Contents/MacOS/caffeinecli status --json
```

Power assertions must be checked against live macOS state when changed. A compile is not proof that macOS accepted an assertion.

Run `make power-check` for the non-disruptive assertion check. `make power-test-screen` and `make power-test-lid` run guided hardware tests and save their evidence under `.build/power-tests/`. Never run either guided test without the user expecting their display or lid state to change.

## Commits and releases

Use conventional commits such as `feat:`, `fix:`, and `chore:`. Update `CHANGELOG.md` for anything a user notices. Never commit certificates, App Store Connect keys, Sparkle private keys, or values from `~/.config/macos`.
