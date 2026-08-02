import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    struct Dependencies {
        let settings: SettingsStore
        let controller: AwakeController
    }

    let updater: any UpdaterProviding = makeUpdaterController()
    private var dependencies: Dependencies?
    private var panelController: PanelController?
    private var settingsWindowController: SettingsWindowController?

    func configure(_ dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.isOnlyRunningInstance(), let dependencies else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        dependencies.settings.registerAtLoginIfNeeded()
        dependencies.controller.start()
        self.panelController = PanelController(
            controller: dependencies.controller,
            settings: dependencies.settings,
            updater: self.updater,
            openSettings: { [weak self] in self?.openSettings() })

        if dependencies.controller.shouldOfferAgentHooks {
            Task { @MainActor [weak self] in self?.offerAgentHooks() }
        }

        switch ProcessInfo.processInfo.environment["CAFFEINE_OPEN_ON_LAUNCH"] {
        case "1": self.panelController?.open()
        case "settings": self.openSettings()
        default: break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.dependencies?.controller.stop()
    }

    func openSettings() {
        guard let dependencies else { return }
        if self.settingsWindowController == nil {
            self.settingsWindowController = SettingsWindowController(
                settings: dependencies.settings,
                controller: dependencies.controller,
                updater: self.updater)
        }
        self.settingsWindowController?.present()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        self.panelController?.open()
        return true
    }

    private func offerAgentHooks() {
        guard let dependencies, dependencies.controller.shouldOfferAgentHooks else { return }
        let alert = NSAlert()
        alert.messageText = "Make Agent Watch turn-aware"
        alert.informativeText = """
        Caffeine can add optional lifecycle hooks to Claude Code and Codex. They turn Agent Watch on while a turn is \
        running, then let your Mac sleep when the agent waits for you.

        Your existing hooks are preserved. You can remove Caffeine's hooks later in Settings.
        """
        alert.addButton(withTitle: "Install Hooks")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        dependencies.controller.dismissAgentHooksOffer()
        guard response == .alertFirstButtonReturn else { return }

        let result = NSAlert()
        if let error = dependencies.controller.installAgentHooks() {
            result.alertStyle = .warning
            result.messageText = "Hooks could not be installed"
            result.informativeText = error
        } else {
            result.messageText = "Lifecycle hooks installed"
            result.informativeText = """
            Restart Claude Code and Codex. Codex will ask you to review the new command hook. Run /hooks and trust \
            Caffeine before the first turn.
            """
        }
        result.addButton(withTitle: "OK")
        result.runModal()
    }

    private static func isOnlyRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        return NSWorkspace.shared.runningApplications.allSatisfy {
            $0.bundleIdentifier != bundleID || $0.processIdentifier == ProcessInfo.processInfo.processIdentifier
        }
    }
}
