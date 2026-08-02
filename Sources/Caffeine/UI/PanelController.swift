import AppKit
import Observation
import SwiftUI

final class CaffeinePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let controller: AwakeController
    private let settingsStore: SettingsStore
    private let updater: any UpdaterProviding
    private let openSettingsAction: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: CaffeinePanel?
    private var outsideClickMonitor: Any?

    init(
        controller: AwakeController,
        settings: SettingsStore,
        updater: any UpdaterProviding,
        openSettings: @escaping () -> Void)
    {
        self.controller = controller
        self.settingsStore = settings
        self.updater = updater
        self.openSettingsAction = openSettings
        super.init()
        self.configureStatusItem()
        self.observeState()
    }

    private func configureStatusItem() {
        guard let button = self.statusItem.button else { return }
        self.statusItem.autosaveName = "CaffeineStatusItem"
        button.target = self
        button.action = #selector(self.statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        self.updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = self.statusItem.button else { return }
        button.image = self.statusImage()
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        button.contentTintColor = nil
        button.toolTip = [
            self.controller.statusTitle,
            self.controller.statusDetail,
            self.settingsStore.clickAction == .toggle
                ? "Click to toggle · Option-click for controls"
                : "Click for controls",
        ].joined(separator: "\n")
    }

    private func statusImage() -> NSImage {
        let cup = CaffeineAssets.statusImage(active: self.controller.isActive)
        guard case .agents = self.controller.policyResult.source else { return cup }

        let diameter: CGFloat = 7
        let moat: CGFloat = 1
        let overhang: CGFloat = 2
        let size = NSSize(width: cup.size.width + overhang + moat, height: cup.size.height)
        let badge = NSRect(x: size.width - diameter - moat, y: 0, width: diameter, height: diameter)

        let image = NSImage(size: size, flipped: false) { _ in
            let cupRect = NSRect(origin: .zero, size: cup.size)
            cup.draw(in: cupRect)
            NSColor.labelColor.set()
            cupRect.fill(using: .sourceAtop)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            NSBezierPath(ovalIn: badge.insetBy(dx: -moat, dy: -moat)).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.systemBlue.setFill()
            NSBezierPath(ovalIn: badge).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func observeState() {
        withObservationTracking {
            _ = self.controller.policyResult
            _ = self.controller.assertionError
            _ = self.settingsStore.clickAction
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStatusItem()
                self.observeState()
            }
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            self.showContextMenu()
        } else if event?.modifierFlags.contains(.option) == true || self.settingsStore.clickAction == .openControls {
            self.togglePanel()
        } else {
            self.controller.toggle()
        }
    }

    func togglePanel() {
        if self.panel?.isVisible == true {
            self.close()
        } else {
            self.open()
        }
    }

    func open() {
        let panel = self.panel ?? self.makePanel()
        self.panel = panel
        self.position(panel)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        self.startMonitoring()
        self.controller.scanNow()
    }

    func close() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        self.panel?.orderOut(nil)
    }

    private func makePanel() -> CaffeinePanel {
        let panel = CaffeinePanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.Panel.width, height: Theme.Panel.height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let root = PanelContentView(
            controller: self.controller,
            settings: self.settingsStore,
            openSettings: self.openSettingsAction,
            dismiss: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let button = self.statusItem.button,
              let window = button.window,
              let screen = window.screen ?? NSScreen.main
        else { return }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let size = panel.frame.size
        var origin = NSPoint(
            x: buttonRect.midX - size.width / 2,
            y: buttonRect.minY - size.height - Theme.Panel.menuBarGap)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = max(origin.y, visible.minY + 8)
        panel.setFrameOrigin(origin)
    }

    private func startMonitoring() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        self.outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown])
        { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Menus and controls inside the panel temporarily take key focus.
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: self.controller.isActive ? "Turn Caffeine Off" : "Turn Caffeine On",
            action: #selector(self.toggle),
            keyEquivalent: "")

        let timerItem = NSMenuItem(title: "Activate For", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for (title, seconds) in [("30 Minutes", 1800), ("1 Hour", 3600), ("2 Hours", 7200), ("8 Hours", 28800)] {
            let item = timerMenu.addItem(withTitle: title, action: #selector(self.activateFor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
        }
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)
        menu.addItem(.separator())

        let watch = menu.addItem(withTitle: "Agent Watch", action: #selector(self.toggleAgentWatch), keyEquivalent: "")
        watch.state = self.settingsStore.agentWatchEnabled ? .on : .off
        menu.addItem(withTitle: "Open Controls…", action: #selector(self.openControls), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(self.settings), keyEquivalent: ",")
        menu.addItem(.separator())
        if self.updater.isAvailable {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(self.checkForUpdates), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Quit Caffeine", action: #selector(self.quit), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }

        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        self.statusItem.menu = nil
    }

    @objc private func toggle() {
        self.controller.toggle()
    }

    @objc private func activateFor(_ sender: NSMenuItem) {
        self.controller.activate(for: TimeInterval(sender.tag))
    }

    @objc private func toggleAgentWatch() {
        self.settingsStore.agentWatchEnabled.toggle()
    }

    @objc private func openControls() {
        self.open()
    }

    @objc private func settings() {
        self.close(); self.openSettingsAction()
    }

    @objc private func checkForUpdates() {
        self.close(); self.updater.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
