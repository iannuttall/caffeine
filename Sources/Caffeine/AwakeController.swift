import CaffeineCore
import Foundation
import Observation

@MainActor
@Observable
final class AwakeController {
    let settings: SettingsStore

    private(set) var manualActive: Bool
    private(set) var manualDeadline: Date?
    private(set) var activeAgents: [ActiveAgent] = []
    private(set) var installedAgents: [InstalledAgent] = []
    private(set) var sleepBlockers: [SleepBlocker] = []
    private(set) var batteryPercent: Int?
    private(set) var isOnBattery = false
    private(set) var smartPaused = false
    private(set) var assertionError: String?
    private(set) var hookStatus: AgentHookInstallStatus
    private(set) var policyResult = AwakePolicyResult(
        shouldStayAwake: false,
        source: .inactive,
        remainingSeconds: nil)

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let assertionManager = PowerAssertionManager()
    @ObservationIgnored private let powerAssertionScanner = PowerAssertionScanner()
    @ObservationIgnored private let processScanner = ProcessScanner()
    @ObservationIgnored private let lifecycleScanner = AgentLifecycleScanner()
    @ObservationIgnored private let hookInstaller: AgentHookInstaller
    @ObservationIgnored private var processAgents: [RunningAgent] = []
    @ObservationIgnored private var lifecycleSessions: [AgentLifecycleSession] = []
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var scanTimer: Timer?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var lastStatusIdentity: StatusIdentity?
    @ObservationIgnored private var lastStatusWrittenAt = Date.distantPast

    init(
        settings: SettingsStore,
        defaults: UserDefaults = UserDefaults(suiteName: CaffeineDefaults.suiteName) ?? .standard,
        hookInstaller: AgentHookInstaller = AgentHookInstaller())
    {
        self.settings = settings
        self.defaults = defaults
        self.hookInstaller = hookInstaller
        self.hookStatus = hookInstaller.status
        self.manualActive = settings.restoreManualSession
            ? defaults.bool(forKey: CaffeineDefaults.Key.manualActive)
            : false
        self.manualDeadline = settings.restoreManualSession
            ? defaults.object(forKey: CaffeineDefaults.Key.manualDeadline) as? Date
            : nil
    }

    var isActive: Bool {
        self.policyResult.shouldStayAwake
    }

    var statusTitle: String {
        switch self.policyResult.source {
        case .inactive: "Caffeine is resting"
        case .manual: "Caffeine is active"
        case .agents: "Agent Watch is active"
        case .batteryPaused: "Paused to protect battery"
        }
    }

    var statusDetail: String {
        if let assertionError {
            return assertionError
        }
        switch self.policyResult.source {
        case .inactive:
            if self.smartPaused, !self.activeAgents.isEmpty {
                return "Agent Watch paused until these agents finish."
            }
            return self.settings.agentWatchEnabled
                ? "Waiting for you or a coding agent."
                : "Your Mac can sleep normally."
        case .manual:
            if let seconds = self.policyResult
                .remainingSeconds
            {
                return "Turns off in \(DurationParser.label(seconds: seconds))."
            }
            return self.settings.closedLidMode
                ? "Manual session · closed-lid assertion requested."
                : "Manual session · no time limit."
        case let .agents(labels):
            let unique = Array(Set(labels)).sorted()
            return "Watching \(unique.joined(separator: ", "))."
        case let .batteryPaused(percent):
            return "Battery is at \(percent)%. Caffeine resumes when power is safe."
        }
    }

    func start() {
        self.refreshPowerSource()
        self.consumeCommand()
        self.evaluate()
        self.scanNow()
        self.refreshLifecycleNow()
        self.observeSettings()

        let tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(tickTimer, forMode: .common)
        self.tickTimer = tickTimer

        let scanTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanNow() }
        }
        RunLoop.main.add(scanTimer, forMode: .common)
        self.scanTimer = scanTimer
    }

    func stop() {
        self.tickTimer?.invalidate()
        self.scanTimer?.invalidate()
        self.scanTask?.cancel()
        self.lifecycleTask?.cancel()
        self.assertionManager.releaseAll()
    }

    func toggle() {
        if self.manualActive {
            self.deactivate()
        } else if self.smartPaused, !self.activeAgents.isEmpty {
            self.smartPaused = false
            self.evaluate()
        } else if self.isActive {
            self.smartPaused = true
            self.evaluate()
        } else {
            self.activate(for: nil)
        }
    }

    func activate(for duration: TimeInterval?) {
        self.manualActive = true
        self.manualDeadline = duration.flatMap { $0 > 0 ? Date().addingTimeInterval($0) : nil }
        self.smartPaused = false
        self.persistManualSession()
        self.evaluate()
    }

    func deactivate() {
        self.manualActive = false
        self.manualDeadline = nil
        if !self.activeAgents.isEmpty {
            self.smartPaused = true
        }
        self.persistManualSession()
        self.evaluate()
    }

    func scanNow() {
        guard self.scanTask == nil else { return }
        let signatures = self.settings.agentSignatures
        let shouldScanProcesses = self.settings.agentWatchEnabled && self.settings.keepAwakeWhileAgentAppsOpen
        self.scanTask = Task { [weak self, powerAssertionScanner, processScanner] in
            async let installed = processScanner.installed(signatures: signatures)
            async let blockers = powerAssertionScanner.scan(excluding: ProcessInfo.processInfo.processIdentifier)
            let agents: [RunningAgent] = if shouldScanProcesses {
                await processScanner.scan(signatures: signatures, includeAppBundles: true)
                    .filter { $0.pid != ProcessInfo.processInfo.processIdentifier }
            } else {
                []
            }
            guard let self, !Task.isCancelled else { return }
            self.processAgents = agents
            self.installedAgents = await installed
            self.sleepBlockers = await blockers
            self.hookStatus = self.hookInstaller.status
            self.rebuildActiveAgents()
            if self.activeAgents.isEmpty {
                self.smartPaused = false
            }
            self.scanTask = nil
            self.evaluate()
        }
    }

    func installAgentHooks() -> String? {
        do {
            self.hookStatus = try self.hookInstaller.install()
            self.settings.didOfferAgentHooks = true
            self.rebuildActiveAgents()
            self.evaluate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeAgentHooks() -> String? {
        do {
            self.hookStatus = try self.hookInstaller.remove()
            self.lifecycleSessions = []
            self.rebuildActiveAgents()
            self.evaluate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func dismissAgentHooksOffer() {
        self.settings.didOfferAgentHooks = true
    }

    var shouldOfferAgentHooks: Bool {
        self.settings.agentWatchEnabled && !self.settings.didOfferAgentHooks && !self.hookStatus.allInstalled
    }

    private func tick() {
        self.consumeCommand()
        self.refreshLifecycleNow()
        self.tickCount += 1
        if self.tickCount.isMultiple(of: 30) {
            self.refreshPowerSource()
        }
        if self.manualActive, let deadline = self.manualDeadline, deadline <= Date() {
            self.manualActive = false
            self.manualDeadline = nil
            self.persistManualSession()
        }
        self.evaluate()
    }

    private func refreshPowerSource() {
        let power = PowerSourceMonitor.current()
        self.batteryPercent = power.batteryPercent
        self.isOnBattery = power.isOnBattery
    }

    private func evaluate() {
        let result = AwakePolicy(
            manualActive: self.manualActive,
            manualDeadline: self.manualDeadline,
            agentWatchEnabled: self.settings.agentWatchEnabled,
            smartPaused: self.smartPaused,
            activeAgents: self.activeAgents,
            batteryPercent: self.batteryPercent,
            isOnBattery: self.isOnBattery,
            batteryCutoff: self.settings.batteryCutoff).result()
        self.policyResult = result
        self.assertionError = self.assertionManager.apply(PowerAssertionPlan(
            active: result.shouldStayAwake,
            allowDisplaySleep: self.settings.allowDisplaySleep,
            keepNetworkActive: self.settings.keepNetworkActive,
            closedLidMode: self.settings.closedLidMode))
        self.persistStatus()
    }

    private func persistManualSession() {
        self.defaults.set(self.manualActive, forKey: CaffeineDefaults.Key.manualActive)
        self.defaults.set(self.manualDeadline, forKey: CaffeineDefaults.Key.manualDeadline)
    }

    private func persistStatus() {
        let agents = Array(Set(self.activeAgents.map(\.label))).sorted()
        let installedAgents = self.installedAgents.map(\.label)
        let identity = StatusIdentity(
            active: self.isActive,
            source: self.statusCategory,
            agents: agents,
            installedAgents: installedAgents,
            batteryPercent: self.batteryPercent)
        let now = Date()
        guard identity != self.lastStatusIdentity || now.timeIntervalSince(self.lastStatusWrittenAt) >= 5 else {
            return
        }
        self.lastStatusIdentity = identity
        self.lastStatusWrittenAt = now

        self.defaults.set(self.isActive, forKey: CaffeineDefaults.Key.statusActive)
        self.defaults.set(self.statusDetail, forKey: CaffeineDefaults.Key.statusSource)
        self.defaults.set(agents, forKey: CaffeineDefaults.Key.statusAgents)
        self.defaults.set(installedAgents, forKey: CaffeineDefaults.Key.statusInstalledAgents)
        self.defaults.set(self.batteryPercent, forKey: CaffeineDefaults.Key.statusBattery)
        self.defaults.set(now, forKey: CaffeineDefaults.Key.statusUpdatedAt)
    }

    private var statusCategory: String {
        switch self.policyResult.source {
        case .inactive: "inactive"
        case .manual: "manual"
        case .agents: "agents"
        case .batteryPaused: "battery-paused"
        }
    }

    private func consumeCommand() {
        guard let revision = self.defaults.string(forKey: CaffeineDefaults.Key.commandRevision),
              revision != self.defaults.string(forKey: CaffeineDefaults.Key.commandHandledRevision),
              let raw = self.defaults.string(forKey: CaffeineDefaults.Key.command),
              let command = CaffeineCommand(rawValue: raw)
        else { return }

        self.defaults.set(revision, forKey: CaffeineDefaults.Key.commandHandledRevision)
        switch command {
        case .activate:
            let duration = self.defaults.object(forKey: CaffeineDefaults.Key.commandDuration) as? Double
            self.activate(for: duration)
        case .deactivate:
            self.deactivate()
        case .toggle:
            self.toggle()
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = self.settings.agentWatchEnabled
            _ = self.settings.agentExecutables
            _ = self.settings.keepAwakeWhileAgentAppsOpen
            _ = self.settings.allowDisplaySleep
            _ = self.settings.keepNetworkActive
            _ = self.settings.closedLidMode
            _ = self.settings.batteryCutoff
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scanNow()
                self.rebuildActiveAgents()
                self.evaluate()
                self.observeSettings()
            }
        }
    }

    private func refreshLifecycleNow() {
        guard self.lifecycleTask == nil else { return }
        self.lifecycleTask = Task { [weak self, lifecycleScanner] in
            let sessions = await lifecycleScanner.scan()
            guard let self, !Task.isCancelled else { return }
            self.lifecycleSessions = sessions
            self.rebuildActiveAgents()
            if self.activeAgents.isEmpty {
                self.smartPaused = false
            }
            self.lifecycleTask = nil
            self.evaluate()
        }
    }

    private func rebuildActiveAgents() {
        var agents = self.lifecycleSessions
            .filter { session in
                switch session.provider {
                case .claude: self.hookStatus.claudeInstalled
                case .codex: self.hookStatus.codexInstalled
                }
            }
            .map(\.activeAgent)
        if self.settings.keepAwakeWhileAgentAppsOpen {
            agents.append(contentsOf: self.processAgents.map(ActiveAgent.init(process:)))
        }
        self.activeAgents = agents.sorted {
            $0.label == $1.label
                ? $0.id < $1.id
                : $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }
}

private struct StatusIdentity: Equatable {
    let active: Bool
    let source: String
    let agents: [String]
    let installedAgents: [String]
    let batteryPercent: Int?
}
