import Foundation

public struct AgentSignature: Codable, Equatable, Hashable, Sendable {
    public let executable: String
    public let label: String

    public init(executable: String, label: String) {
        self.executable = executable
        self.label = label
    }

    public static let defaults = [
        AgentSignature(executable: "codex", label: "Codex"),
        AgentSignature(executable: "claude", label: "Claude Code"),
        AgentSignature(executable: "opencode", label: "OpenCode"),
        AgentSignature(executable: "aider", label: "Aider"),
        AgentSignature(executable: "amp", label: "Amp"),
        AgentSignature(executable: "gemini", label: "Gemini CLI"),
        AgentSignature(executable: "cursor-agent", label: "Cursor Agent"),
        AgentSignature(executable: "goose", label: "Goose"),
    ]
}

public struct RunningAgent: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let pid: Int32
    public let executable: String
    public let label: String

    public var id: Int32 {
        self.pid
    }

    public init(pid: Int32, executable: String, label: String) {
        self.pid = pid
        self.executable = executable
        self.label = label
    }
}

public struct InstalledAgent: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let executable: String
    public let label: String
    public let path: String

    public var id: String {
        self.executable
    }

    public init(executable: String, label: String, path: String) {
        self.executable = executable
        self.label = label
        self.path = path
    }
}

public enum ProcessListParser {
    public static func agents(
        in output: String,
        signatures: [AgentSignature],
        includeAppBundles: Bool = false) -> [RunningAgent]
    {
        let labels = Dictionary(uniqueKeysWithValues: signatures.map { ($0.executable.lowercased(), $0.label) })
        var result: [RunningAgent] = []

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count >= 2, let pid = Int32(fields[0]) else { continue }

            let commandPath = String(fields[1])
            let command = URL(fileURLWithPath: commandPath).lastPathComponent.lowercased()
            let arguments = fields.count == 3 ? String(fields[2]) : ""
            let executable = labels[command] == nil ? self.matchingExecutable(in: arguments, labels: labels) : command
            guard let executable, let label = labels[executable] else { continue }
            if self.isAppBundleProcess(commandPath: commandPath, arguments: arguments) {
                guard includeAppBundles,
                      self.isMainAppProcess(executable: executable, commandPath: commandPath, arguments: arguments)
                else { continue }
            }
            guard !self.isPersistentHost(executable: executable, arguments: arguments) else { continue }

            result.append(RunningAgent(pid: pid, executable: executable, label: label))
        }

        return result.sorted {
            $0.label == $1.label ? $0.pid < $1.pid : $0.label
                .localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    private static func matchingExecutable(in arguments: String, labels: [String: String]) -> String? {
        let words = arguments.split(whereSeparator: \.isWhitespace).map {
            URL(fileURLWithPath: String($0)).lastPathComponent.lowercased()
        }
        return words.first(where: { labels[$0] != nil })
    }

    private static func isPersistentHost(executable: String, arguments: String) -> Bool {
        let words = arguments.lowercased().split(whereSeparator: \.isWhitespace)
        return executable == "codex" && words.contains("app-server")
    }

    private static func isAppBundleProcess(commandPath: String, arguments: String) -> Bool {
        if commandPath.localizedCaseInsensitiveContains(".app/Contents/") { return true }
        guard let appRange = arguments.range(of: ".app/Contents/", options: .caseInsensitive) else { return false }
        guard let optionRange = arguments.range(of: " --") else { return true }
        return appRange.lowerBound < optionRange.lowerBound
    }

    private static func isMainAppProcess(executable: String, commandPath: String, arguments: String) -> Bool {
        let expectedPath = "/\(executable).app/contents/macos/\(executable)"
        return commandPath.lowercased().contains(expectedPath) || arguments.lowercased().contains(expectedPath)
    }
}

public struct AwakePolicy: Equatable, Sendable {
    public let manualActive: Bool
    public let manualDeadline: Date?
    public let agentWatchEnabled: Bool
    public let smartPaused: Bool
    public let activeAgents: [ActiveAgent]
    public let batteryPercent: Int?
    public let isOnBattery: Bool
    public let batteryCutoff: Int

    public init(
        manualActive: Bool,
        manualDeadline: Date?,
        agentWatchEnabled: Bool,
        smartPaused: Bool,
        activeAgents: [ActiveAgent],
        batteryPercent: Int?,
        isOnBattery: Bool,
        batteryCutoff: Int)
    {
        self.manualActive = manualActive
        self.manualDeadline = manualDeadline
        self.agentWatchEnabled = agentWatchEnabled
        self.smartPaused = smartPaused
        self.activeAgents = activeAgents
        self.batteryPercent = batteryPercent
        self.isOnBattery = isOnBattery
        self.batteryCutoff = batteryCutoff
    }

    public func result(at date: Date = Date()) -> AwakePolicyResult {
        let manualHasTime = self.manualDeadline.map { $0 > date } ?? true
        let manual = self.manualActive && manualHasTime
        let agents = self.agentWatchEnabled && !self.smartPaused && !self.activeAgents.isEmpty
        let requested = manual || agents

        if requested,
           self.batteryCutoff > 0,
           self.isOnBattery,
           let percent = self.batteryPercent,
           percent <= self.batteryCutoff
        {
            return AwakePolicyResult(
                shouldStayAwake: false,
                source: .batteryPaused(percent: percent),
                remainingSeconds: nil)
        }

        if manual {
            let remaining = self.manualDeadline.map { max(0, Int(ceil($0.timeIntervalSince(date)))) }
            return AwakePolicyResult(shouldStayAwake: true, source: .manual, remainingSeconds: remaining)
        }

        if agents {
            return AwakePolicyResult(
                shouldStayAwake: true,
                source: .agents(self.activeAgents.map(\.label)),
                remainingSeconds: nil)
        }

        return AwakePolicyResult(shouldStayAwake: false, source: .inactive, remainingSeconds: nil)
    }
}

public struct AwakePolicyResult: Equatable, Sendable {
    public let shouldStayAwake: Bool
    public let source: AwakeSource
    public let remainingSeconds: Int?

    public init(shouldStayAwake: Bool, source: AwakeSource, remainingSeconds: Int?) {
        self.shouldStayAwake = shouldStayAwake
        self.source = source
        self.remainingSeconds = remainingSeconds
    }
}

public enum AwakeSource: Equatable, Sendable {
    case inactive
    case manual
    case agents([String])
    case batteryPaused(percent: Int)
}

public enum DurationParser {
    public static func seconds(from value: String) -> TimeInterval? {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !input.isEmpty else { return nil }
        if input == "infinity" || input == "indefinite" || input == "forever" { return 0 }

        let unit = input.last
        let number: String
        let multiplier: Double
        switch unit {
        case "m":
            number = String(input.dropLast())
            multiplier = 60
        case "h":
            number = String(input.dropLast())
            multiplier = 3600
        case "d":
            number = String(input.dropLast())
            multiplier = 86400
        default:
            number = input
            multiplier = 60
        }
        guard let amount = Double(number), amount > 0 else { return nil }
        return amount * multiplier
    }

    public static func label(seconds: Int) -> String {
        let safe = max(0, seconds)
        if safe < 60 { return "\(safe)s" }
        let minutes = safe / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
