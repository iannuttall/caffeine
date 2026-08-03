# What came from the reference audit

The two cloned apps and the existing Scheduler and Portman apps pointed at a clear product shape.

| Source | Kept | Changed |
| --- | --- | --- |
| Original Caffeine | Cup identity, empty and full states, one-click toggle, timers, login item | Replaced Combine, Xcode project wiring, repeated short assertions, and fake activity with SwiftPM, Observation, long-lived IOKit assertions, and tested policy code |
| Code Awake | Separate system, network, display, and closed-lid assertions; battery protection | Moved policy into a portable target, kept the classic display-awake default, and kept the lid claim deliberately limited |
| Scheduler | Config-driven bundle identity, SwiftPM core and CLI split, Swift Testing, strict formatting, Developer ID release pipeline | Adapted the CLI to shared live state rather than scheduled task files |
| Portman | Keyable fixed-size panel, status item rendering rules, live-process inspection, real launch verification | Preserved Caffeine's faster one-click behavior and used the panel as an optional control surface |
| Agents Sleep Preventer | Claude Code and Codex lifecycle hooks that distinguish active work from waiting | Kept public IOKit assertions, added safe hook merging, and left process watching as an optional fallback |

No source code was copied from the cloned projects. The upstream Caffeine menu-bar and app-icon artwork is reused under its MIT license, with the original copyright notice kept in the repository.

## Ideas that fit a later release

- A session history could show which agent kept the Mac awake and for how long. That would make battery cost visible instead of guessing.
- A completion notification could fire when the last lifecycle marker clears. It should be opt-in because a completed turn does not always need attention.
- Per-project rules could watch a command plus a working directory. Process arguments already provide enough input, but the matching UI needs care.
- A thermal cutoff could pause new work when macOS reports a serious or critical thermal state. Existing work should not be killed.
- Shortcuts actions could expose On, Off, For Duration, and Status without duplicating CLI logic.
