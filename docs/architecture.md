# How Caffeine is put together

The app has three targets.

`CaffeineCore` decides when a session should be active, parses durations, and identifies agent processes from a `ps` snapshot. It stays portable so the important behavior can be tested without launching a macOS app.

`caffeinecli` writes commands and reads status through the `com.iannuttall.caffeine.shared` defaults suite. The app checks command revisions once per second. This avoids Apple Events, accessibility permissions, sockets, and a background helper.

`Caffeine` owns the menu bar UI and macOS services. `AwakeController` combines manual state, detected agents, battery state, and settings into one `AwakePolicyResult`. `PowerAssertionManager` translates that result into IOKit assertions.

`PowerAssertionScanner` reads macOS's public per-process assertion catalog every eight seconds. It resolves assertions created on behalf of another process, groups them by owner, and excludes Caffeine itself. The Power pane shows the process, PID, reason, and assertion type without offering to terminate system services.

```text
menu bar / panel / CLI command
             |
       AwakeController
        /     |      \
manual state agents  battery
        \     |      /
          AwakePolicy
               |
   PowerAssertionManager
```

The UI reads a warm observable snapshot. Process scanning runs in an actor because `/bin/ps` can block. The app scans every eight seconds and updates timer and battery state every second.

## Power assertion plan

Every active session gets `PreventUserIdleSystemSleep` and, by default, `PreventUserIdleDisplaySleep`. `NetworkClientActive` is enabled by default. Users can allow display sleep for unattended runs while keeping the Mac and network awake. Closed-lid mode adds `PreventSystemSleep` as a best-effort request.

The manager applies complete plans. A setting change releases every old assertion before creating the new set. If any creation fails, it releases the partial set and reports the failure in the UI.
