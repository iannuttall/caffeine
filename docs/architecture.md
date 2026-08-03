# How Caffeine is put together

Caffeine has three SwiftPM targets.

`CaffeineCore` owns portable policy, duration parsing, agent process parsing, lifecycle marker
storage, and safe hook configuration editing. It does not import AppKit, SwiftUI, or IOKit, so
the important behavior can be tested without launching the app.

`caffeinecli` sends manual commands through the shared user defaults suite. Its private
`agent-event` command receives lifecycle hook payloads on standard input and updates the marker
for that agent session. Hook errors are swallowed because a broken sleep helper must never stop
Claude Code or Codex.

`Caffeine` owns the menu bar UI and macOS services. `AwakeController` combines manual state,
active lifecycle markers, optional process matches, battery state, and settings into one
`AwakePolicyResult`. `PowerAssertionManager` turns that result into IOKit assertions.

```text
menu bar / panel / CLI command / lifecycle hook
                     |
               AwakeController
              /      |       \
      manual state  agents  battery
              \      |       /
                 AwakePolicy
                      |
          PowerAssertionManager
```

## Agent Watch activity

Claude Code and Codex lifecycle hooks are the preferred activity source. A prompt or tool event
creates or refreshes a per-session marker under Application Support. Stop, session end, and
input-waiting events remove it. Markers have a stale cap so an interrupted hook cannot hold an
assertion forever.

The installer edits `~/.claude/settings.json` and `~/.codex/hooks.json` as structured JSON. It
removes older Caffeine handlers before adding the current set. Every other handler and setting
is preserved. An unreadable file, unfamiliar hook structure, or concurrent edit aborts the
operation without replacing the user's config.

Process watching is a separate fallback. When enabled, `ProcessScanner` runs `/bin/ps` in an
actor and feeds its output to the portable parser. Main agent app processes can match, but app
helpers and persistent desktop hosts do not. With the fallback disabled, an idle agent app does
not keep Caffeine active.

## Power assertions

Every active session gets `PreventUserIdleSystemSleep` and, by default,
`PreventUserIdleDisplaySleep`. `NetworkClientActive` is enabled by default. Users can allow the
display to sleep while the Mac and network remain awake. Closed-lid mode adds
`PreventSystemSleep` as a best-effort request.

The manager replaces complete assertion plans. A setting change releases every old assertion
before creating the new set. If any creation fails, it releases the partial set and reports the
failure in the UI.

`PowerAssertionScanner` reads macOS's public per-process assertion catalog every eight seconds.
It resolves assertions created on behalf of another process, groups them by owner, and excludes
Caffeine itself. The Power pane is read-only and never offers to terminate a system service.

## UI and shared state

The app updates timers, lifecycle markers, and battery state once per second. Process and power
scans stay off the main actor. The panel owns a fixed size so changing timer text cannot move it
away from the menu bar.

The CLI and app share `com.iannuttall.caffeine.shared` user defaults. Commands carry a unique
revision, which lets the app consume each request once without Apple Events, accessibility
permissions, a socket, or a background helper.
