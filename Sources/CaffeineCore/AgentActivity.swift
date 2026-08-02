import Foundation

public enum AgentActivitySource: String, Codable, Equatable, Sendable {
    case lifecycle
    case process
}

public struct ActiveAgent: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let executable: String
    public let label: String
    public let pid: Int32?
    public let source: AgentActivitySource

    public init(
        id: String,
        executable: String,
        label: String,
        pid: Int32?,
        source: AgentActivitySource)
    {
        self.id = id
        self.executable = executable
        self.label = label
        self.pid = pid
        self.source = source
    }

    public init(process: RunningAgent) {
        self.init(
            id: "process-\(process.pid)",
            executable: process.executable,
            label: process.label,
            pid: process.pid,
            source: .process)
    }
}

public enum AgentLifecycleProvider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex

    public var executable: String {
        self.rawValue
    }

    public var label: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

public enum AgentLifecycleAction: String, Codable, Sendable {
    case refresh
    case start
    case stop
    case wait
}

public struct AgentLifecycleSession: Codable, Equatable, Identifiable, Sendable {
    public let sessionID: String
    public let provider: AgentLifecycleProvider
    public let updatedAt: Date

    public var id: String {
        "\(self.provider.rawValue)-\(self.sessionID)"
    }

    public var activeAgent: ActiveAgent {
        ActiveAgent(
            id: "lifecycle-\(self.id)",
            executable: self.provider.executable,
            label: self.provider.label,
            pid: nil,
            source: .lifecycle)
    }

    public init(sessionID: String, provider: AgentLifecycleProvider, updatedAt: Date) {
        self.sessionID = sessionID
        self.provider = provider
        self.updatedAt = updatedAt
    }
}

public struct AgentHookPayload: Decodable, Equatable, Sendable {
    public let sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}
