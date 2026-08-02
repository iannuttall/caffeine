import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore, controller: AwakeController, updater: any UpdaterProviding) {
        let hosting = NSHostingController(rootView: SettingsView(
            settings: settings,
            controller: controller,
            updater: updater))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Caffeine"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 540))
        window.minSize = NSSize(width: 700, height: 500)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        self.showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
