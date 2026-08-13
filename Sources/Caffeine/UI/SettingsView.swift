import AppKit
import CaffeineCore
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case agents
    case power
    case commandLine
    case about

    var id: String {
        self.rawValue
    }

    var label: String {
        switch self {
        case .general: "General"
        case .agents: "Agents"
        case .power: "Power"
        case .commandLine: "Command Line"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .agents: "terminal"
        case .power: "bolt"
        case .commandLine: "chevron.left.forwardslash.chevron.right"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: AwakeController
    let updater: any UpdaterProviding
    @State private var pane = SettingsPane.general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: self.$pane) { pane in
                Label(pane.label, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 210)
        } detail: {
            Group {
                switch self.pane {
                case .general: GeneralSettingsPane(settings: self.settings)
                case .agents: AgentSettingsPane(settings: self.settings, controller: self.controller)
                case .power: PowerSettingsPane(settings: self.settings, controller: self.controller)
                case .commandLine: CommandLineSettingsPane()
                case .about: AboutSettingsPane(updater: self.updater)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 540)
    }
}

private struct GeneralSettingsPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        SettingsPage(title: "General", subtitle: "Keep the familiar cup simple, with modern controls nearby.") {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Start Caffeine automatically at login", isOn: self.$settings.launchAtLogin)
                    if let error = self.settings.launchAtLoginError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Toggle(
                        "Restore a manual session after Caffeine restarts",
                        isOn: self.$settings.restoreManualSession)
                    LabeledContent("Clicking the cup") {
                        Picker("Clicking the cup", selection: self.$settings.clickAction) {
                            ForEach(StatusClickAction.allCases) { action in
                                Text(action.label).tag(action)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    Text("Right-click always opens quick controls. Option-click always opens the control panel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            Spacer()
        }
    }
}

private struct AgentSettingsPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: AwakeController
    @State private var hookMessage: String?
    @State private var hookMessageIsError = false

    var body: some View {
        ScrollView {
            SettingsPage(
                title: "Agent Watch",
                subtitle: "Stay awake for active turns, then release the assertion when an agent waits for you.")
            {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Turn on Agent Watch", isOn: self.$settings.agentWatchEnabled)
                        Divider()
                        Text("Lifecycle hooks").font(.headline)
                        Text(
                            "Recommended for Claude Code and Codex. Hooks tell Caffeine when a turn starts, "
                                + "needs your input, or finishes. Existing hooks are preserved.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        self.hookStatus
                        HStack {
                            Button(self.controller.hookStatus.anyInstalled ? "Repair Hooks" : "Install Hooks") {
                                self.installHooks()
                            }
                            .buttonStyle(.borderedProminent)
                            if self.controller.hookStatus.anyInstalled {
                                Button("Remove Hooks") { self.removeHooks() }
                            }
                        }
                        if self.controller.hookStatus.codexInstalled {
                            Text("Restart Codex, run /hooks, then trust the Caffeine hook when Codex asks.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let hookMessage {
                            Text(hookMessage)
                                .font(.footnote)
                                .foregroundStyle(self.hookMessageIsError ? .red : .green)
                        }
                        Divider()
                        Toggle(
                            "Keep awake while an agent app is open",
                            isOn: self.$settings.keepAwakeWhileAgentAppsOpen)
                        Text(
                            "This uses process scanning instead of turn activity. It can keep Caffeine on all day "
                                + "if you leave an agent open.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if self.settings.keepAwakeWhileAgentAppsOpen {
                            Text("Executable names, separated by commas")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("codex, claude, aider", text: self.$settings.agentExecutables, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(2...4)
                        }
                    }
                    .padding(8)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active now").font(.headline)
                        if self.controller.activeAgents.isEmpty {
                            Label("No agent turns are active", systemImage: "moon.zzz")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(self.controller.activeAgents) { agent in
                                HStack {
                                    Circle().fill(.green).frame(width: 7, height: 7)
                                    Text(agent.label)
                                    Spacer()
                                    Text(self.agentDetail(agent))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Divider()
                        Text("Installed tools").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(self.installedAgentsDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Scan Now") { self.controller.scanNow() }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var hookStatus: some View {
        HStack(spacing: 14) {
            Label(
                "Claude Code",
                systemImage: self.controller.hookStatus.claudeInstalled ? "checkmark.circle.fill" : "circle")
            Label(
                "Codex",
                systemImage: self.controller.hookStatus.codexInstalled ? "checkmark.circle.fill" : "circle")
        }
        .font(.footnote)
        .foregroundStyle(self.controller.hookStatus.allInstalled ? .green : .secondary)
    }

    private var installedAgentsDescription: String {
        self.controller.installedAgents.isEmpty
            ? "None found in the usual command-line locations."
            : self.controller.installedAgents.map(\.label).joined(separator: "  ·  ")
    }

    private func agentDetail(_ agent: ActiveAgent) -> String {
        if let pid = agent.pid {
            return "PID \(pid)"
        }
        return "hook"
    }

    private func installHooks() {
        if let error = self.controller.installAgentHooks() {
            self.hookMessage = error
            self.hookMessageIsError = true
        } else {
            self.hookMessage = "Hooks installed. Restart Claude Code and Codex."
            self.hookMessageIsError = false
        }
    }

    private func removeHooks() {
        if let error = self.controller.removeAgentHooks() {
            self.hookMessage = error
            self.hookMessageIsError = true
        } else {
            self.hookMessage = "Caffeine hooks removed."
            self.hookMessageIsError = false
        }
    }
}

private struct PowerSettingsPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: AwakeController

    var body: some View {
        ScrollView {
            SettingsPage(title: "Power", subtitle: "Use the weakest assertion that keeps the work safe.") {
                GroupBox {
                    VStack(alignment: .leading, spacing: 15) {
                        Toggle("Allow the display to sleep", isOn: self.$settings.allowDisplaySleep)
                        Text(
                            "Turn this on for unattended runs when you want the screen off "
                                + "but the Mac and network awake.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Toggle("Keep network client sessions active", isOn: self.$settings.keepNetworkActive)
                        Toggle("Request closed-lid operation", isOn: self.$settings.closedLidMode)
                        Text(
                            "This adds macOS's system-sleep assertion. Lid behaviour is still controlled by macOS "
                                + "and hardware. Reliable clamshell operation may require power, an external display, "
                                + "and an input device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Divider()
                        HStack {
                            Text("Pause on battery at")
                            Slider(
                                value: Binding(
                                    get: { Double(self.settings.batteryCutoff) },
                                    set: { self.settings.batteryCutoff = Int($0.rounded()) }),
                                in: 0...30,
                                step: 5)
                            Text(self.settings.batteryCutoff == 0 ? "Off" : "\(self.settings.batteryCutoff)%")
                                .frame(width: 38, alignment: .trailing)
                                .monospacedDigit()
                        }
                        if let battery = self.controller.batteryPercent {
                            let powerDescription = self.controller.isOnBattery ? "on battery" : "connected to power"
                            Label(
                                "Battery \(battery)% · \(powerDescription)",
                                systemImage: self.controller.isOnBattery ? "battery.50percent" : "bolt.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
                self.sleepBlockers
            }
        }
    }

    private var sleepBlockers: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if self.controller.sleepBlockers.isEmpty {
                    Label("No other processes are blocking sleep", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(self.controller.sleepBlockers.enumerated()), id: \.element.id) { index, blocker in
                        SleepBlockerRow(blocker: blocker)
                        if index < self.controller.sleepBlockers.count - 1 {
                            Divider()
                        }
                    }
                }
                HStack {
                    Text("Caffeine's own assertions are hidden from this list.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { self.controller.scanNow() }
                }
            }
            .padding(8)
        } label: {
            Text("Other sleep blockers")
        }
    }
}

private struct SleepBlockerRow: View {
    let blocker: SleepBlocker

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            self.icon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(self.blocker.processName).font(.body.weight(.medium))
                    if let via = self.blocker.viaProcessName {
                        Text("via \(via)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: "PID \(self.blocker.pid)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(self.reasonSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(self.blocker.assertions.map(\.reason).joined(separator: "\n"))
                HStack(spacing: 5) {
                    ForEach(self.kinds, id: \.self) { kind in
                        BlockerKindPill(text: kind.label)
                    }
                    if let startedAt = self.startedAt {
                        Spacer()
                        Text("since \(startedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var icon: some View {
        if let image = NSRunningApplication(processIdentifier: self.blocker.pid)?.icon {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: self.blocker.processName == "caffeinate" ? "terminal" : "gearshape.2")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    private var kinds: [SleepAssertionKind] {
        Array(Set(self.blocker.assertions.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
    }

    private var reasonSummary: String {
        Array(Set(self.blocker.assertions.map(\.reason))).sorted().prefix(2).joined(separator: " · ")
    }

    private var startedAt: Date? {
        self.blocker.assertions.compactMap(\.startedAt).min()
    }
}

private struct BlockerKindPill: View {
    let text: String

    var body: some View {
        Text(self.text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
    }
}

private struct CommandLineSettingsPane: View {
    @State private var message: String?

    var body: some View {
        SettingsPage(title: "Command Line", subtitle: "Give scripts and agents direct control without UI automation.") {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Install the `caffeine` command").font(.headline)
                    Text("Installs to ~/.local/bin/caffeine and talks to the same app state.")
                        .foregroundStyle(.secondary)
                    Text("caffeine status --json\ncaffeine on\ncaffeine for 2h\ncaffeine off")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    HStack {
                        Button("Install CLI") { self.installCLI() }.buttonStyle(.borderedProminent)
                        if let message {
                            Text(message).font(.footnote)
                                .foregroundStyle(message.hasPrefix("Installed") ? .green : .red)
                        }
                    }
                }
                .padding(8)
            }
            Spacer()
        }
    }

    private func installCLI() {
        do {
            guard let executable = Bundle.main.executableURL else { throw CLIInstallError.missingApp }
            let source = executable.deletingLastPathComponent().appendingPathComponent("caffeinecli")
            guard FileManager.default.fileExists(atPath: source.path) else { throw CLIInstallError.missingCLI }
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
            let destination = directory.appendingPathComponent("caffeine")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            self.message = "Installed to ~/.local/bin/caffeine"
        } catch {
            self.message = error.localizedDescription
        }
    }
}

private enum CLIInstallError: LocalizedError {
    case missingApp
    case missingCLI

    var errorDescription: String? {
        switch self {
        case .missingApp: "Could not locate the app bundle."
        case .missingCLI: "This build does not contain the CLI."
        }
    }
}

private struct AboutSettingsPane: View {
    let updater: any UpdaterProviding

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: CaffeineAssets.cupImage())
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)
            Text("Caffeine").font(.title2.weight(.semibold))
            Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            Text("The familiar cup, rebuilt for long coding sessions and autonomous agents.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Check for Updates…") { self.updater.checkForUpdates() }
                .disabled(!self.updater.isAvailable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.title).font(.title2.weight(.semibold))
                Text(self.subtitle).foregroundStyle(.secondary)
            }
            self.content
        }
        .padding(28)
    }
}
