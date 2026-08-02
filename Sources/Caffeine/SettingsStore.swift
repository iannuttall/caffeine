import CaffeineCore
import Foundation
import Observation
import ServiceManagement

enum StatusClickAction: String, CaseIterable, Identifiable {
    case toggle
    case openControls

    var id: String {
        self.rawValue
    }

    var label: String {
        switch self {
        case .toggle: "Toggle Caffeine"
        case .openControls: "Open controls"
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    var launchAtLogin: Bool {
        didSet { self.save(self.launchAtLogin, for: Key.launchAtLogin); self.applyLoginItem() }
    }

    var clickAction: StatusClickAction {
        didSet { self.save(self.clickAction.rawValue, for: Key.clickAction) }
    }

    var agentWatchEnabled: Bool {
        didSet { self.save(self.agentWatchEnabled, for: Key.agentWatchEnabled) }
    }

    var agentExecutables: String {
        didSet { self.save(self.agentExecutables, for: Key.agentExecutables) }
    }

    var keepAwakeWhileAgentAppsOpen: Bool {
        didSet { self.save(self.keepAwakeWhileAgentAppsOpen, for: Key.keepAwakeWhileAgentAppsOpen) }
    }

    var allowDisplaySleep: Bool {
        didSet { self.save(self.allowDisplaySleep, for: Key.allowDisplaySleep) }
    }

    var keepNetworkActive: Bool {
        didSet { self.save(self.keepNetworkActive, for: Key.keepNetworkActive) }
    }

    var closedLidMode: Bool {
        didSet { self.save(self.closedLidMode, for: Key.closedLidMode) }
    }

    var batteryCutoff: Int {
        didSet { self.save(self.batteryCutoff, for: Key.batteryCutoff) }
    }

    var restoreManualSession: Bool {
        didSet { self.save(self.restoreManualSession, for: Key.restoreManualSession) }
    }

    var didOfferAgentHooks: Bool {
        didSet { self.save(self.didOfferAgentHooks, for: Key.didOfferAgentHooks) }
    }

    var launchAtLoginError: String?

    init(defaults: UserDefaults = UserDefaults(suiteName: CaffeineDefaults.suiteName) ?? .standard) {
        self.defaults = defaults
        self.launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
        self.clickAction = StatusClickAction(rawValue: defaults.string(forKey: Key.clickAction) ?? "") ?? .toggle
        self.agentWatchEnabled = defaults.object(forKey: Key.agentWatchEnabled) as? Bool ?? true
        self.agentExecutables = defaults.string(forKey: Key.agentExecutables)
            ?? AgentSignature.defaults.map(\.executable).joined(separator: ", ")
        self.keepAwakeWhileAgentAppsOpen = defaults.object(forKey: Key.keepAwakeWhileAgentAppsOpen) as? Bool ?? false
        self.allowDisplaySleep = defaults.object(forKey: Key.allowDisplaySleep) as? Bool ?? false
        self.keepNetworkActive = defaults.object(forKey: Key.keepNetworkActive) as? Bool ?? true
        self.closedLidMode = defaults.object(forKey: Key.closedLidMode) as? Bool ?? false
        self.batteryCutoff = defaults.object(forKey: Key.batteryCutoff) as? Int ?? 15
        self.restoreManualSession = defaults.object(forKey: Key.restoreManualSession) as? Bool ?? true
        self.didOfferAgentHooks = defaults.bool(forKey: Key.didOfferAgentHooks)
    }

    var agentSignatures: [AgentSignature] {
        let known = Dictionary(uniqueKeysWithValues: AgentSignature.defaults.map { ($0.executable, $0.label) })
        return self.agentExecutables
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .map { AgentSignature(executable: $0, label: known[$0] ?? $0) }
    }

    func registerAtLoginIfNeeded() {
        guard self.launchAtLogin else { return }
        self.applyLoginItem()
    }

    private func applyLoginItem() {
        do {
            if self.launchAtLogin {
                if SMAppService.mainApp.status == .notRegistered { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            self.launchAtLoginError = SMAppService.mainApp.status == .requiresApproval
                ? "Allow Caffeine in System Settings → General → Login Items."
                : nil
        } catch {
            self.launchAtLoginError = error.localizedDescription
        }
    }

    private func save(_ value: some Any, for key: String) {
        self.defaults.set(value, forKey: key)
    }

    private enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let clickAction = "clickAction"
        static let agentWatchEnabled = "agentWatchEnabled"
        static let agentExecutables = "agentExecutables"
        static let keepAwakeWhileAgentAppsOpen = "keepAwakeWhileAgentAppsOpen"
        static let allowDisplaySleep = "allowDisplaySleep"
        static let keepNetworkActive = "keepNetworkActive"
        static let closedLidMode = "closedLidMode"
        static let batteryCutoff = "batteryCutoff"
        static let restoreManualSession = "restoreManualSession"
        static let didOfferAgentHooks = "didOfferAgentHooks"
    }
}
