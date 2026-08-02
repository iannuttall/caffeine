import CaffeineCore
import SwiftUI

struct PanelContentView: View {
    @Bindable var controller: AwakeController
    @Bindable var settings: SettingsStore
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.roomy) {
            self.header
            self.quickTimers
            self.agentWatch
            self.powerSummary
            if !self.controller.sleepBlockers.isEmpty { self.sleepBlockers }
            Spacer(minLength: 0)
            self.footer
        }
        .padding(16)
        .frame(width: Theme.Panel.width, height: Theme.Panel.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Panel.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Panel.cornerRadius).stroke(Theme.Colour.border)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: CaffeineAssets.statusImage(active: self.controller.isActive))
                .foregroundStyle(self.controller.isActive ? .primary : .secondary)
                .frame(width: 34, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(self.controller.statusTitle).font(.headline)
                Text(self.controller.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(self.controller.isActive ? "Stop" : "Start") {
                self.controller.toggle()
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
    }

    private var quickTimers: some View {
        CaffeineCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keep awake for").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    self.timerButton("30m", seconds: 1800)
                    self.timerButton("1h", seconds: 3600)
                    self.timerButton("2h", seconds: 7200)
                    self.timerButton("∞", seconds: nil)
                }
            }
        }
    }

    private var agentWatch: some View {
        CaffeineCard {
            VStack(alignment: .leading, spacing: 7) {
                Toggle("Agent Watch", isOn: self.$settings.agentWatchEnabled)
                    .font(.body.weight(.medium))
                Text(
                    "Uses lifecycle hooks for active Codex and Claude turns. Process scanning is optional in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !self.controller.activeAgents.isEmpty {
                    let labels = Array(Set(self.controller.activeAgents.map(\.label))).sorted()
                    HStack(spacing: 6) {
                        ForEach(Array(labels.prefix(3)), id: \.self) { label in
                            StatusPill(text: label)
                        }
                        if labels.count > 3 {
                            StatusPill(text: "+\(labels.count - 3)", color: .secondary, showsDot: false)
                        }
                    }
                }
            }
        }
    }

    private var powerSummary: some View {
        CaffeineCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    Label(
                        self.settings.allowDisplaySleep ? "Display may sleep" : "Display stays on",
                        systemImage: self.settings.allowDisplaySleep ? "display" : "sun.max.fill")
                    Spacer()
                    if let battery = self.controller.batteryPercent {
                        Label(
                            "\(battery)%",
                            systemImage: self.controller.isOnBattery ? "battery.50percent" : "bolt.fill")
                    }
                    if self.settings.closedLidMode {
                        Image(systemName: "laptopcomputer.and.arrow.down")
                            .help("Closed-lid assertion is enabled")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var blockerCountLabel: String {
        let count = self.controller.sleepBlockers.count
        return "\(count) other sleep blocker\(count == 1 ? "" : "s")"
    }

    private var sleepBlockers: some View {
        CaffeineCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label(self.blockerCountLabel, systemImage: "moon.zzz.fill")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("Power settings").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(self.controller.sleepBlockers.prefix(3))) { blocker in
                    HStack(spacing: 7) {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                        Text(blocker.processName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        if let via = blocker.viaProcessName {
                            Text("via \(via)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(blocker.assertions.first?.kind.label ?? "Power activity")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(verbatim: String(blocker.pid))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .help(blocker.assertions.map(\.reason).joined(separator: "\n"))
                }
                if self.controller.sleepBlockers.count > 3 {
                    Text("+\(self.controller.sleepBlockers.count - 3) more in Power settings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") {
                self.dismiss()
                self.openSettings()
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Right-click the cup for quick controls")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
        }
        .font(.caption)
    }

    private func timerButton(_ title: String, seconds: TimeInterval?) -> some View {
        Button(title) { self.controller.activate(for: seconds) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
    }
}
