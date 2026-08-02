import Foundation

public struct AgentLifecycleStore: Sendable {
    public static let staleInterval: TimeInterval = 12 * 60 * 60

    public let directory: URL

    public init(directory: URL = Self.defaultDirectory()) {
        self.directory = directory
    }

    public func apply(
        action: AgentLifecycleAction,
        provider: AgentLifecycleProvider,
        payload: AgentHookPayload,
        at date: Date = Date()) throws
    {
        let url = self.fileURL(sessionID: payload.sessionID, provider: provider)
        switch action {
        case .start, .refresh:
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let session = AgentLifecycleSession(sessionID: payload.sessionID, provider: provider, updatedAt: date)
            let data = try JSONEncoder().encode(session)
            try data.write(to: url, options: .atomic)
        case .stop, .wait:
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func activeSessions(at date: Date = Date()) -> [AgentLifecycleSession] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: self.directory,
            includingPropertiesForKeys: nil)
        else { return [] }

        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let session = try? JSONDecoder().decode(AgentLifecycleSession.self, from: data)
            else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            guard date.timeIntervalSince(session.updatedAt) < Self.staleInterval else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return session
        }
        .sorted { left, right in
            left.provider.label == right.provider.label
                ? left.sessionID < right.sessionID
                : left.provider.label.localizedCaseInsensitiveCompare(right.provider.label) == .orderedAscending
        }
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: self.directory)
    }

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Caffeine/AgentSessions", isDirectory: true)
    }

    private func fileURL(sessionID: String, provider: AgentLifecycleProvider) -> URL {
        let encoded = Data(sessionID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return self.directory.appendingPathComponent("\(provider.rawValue)-\(encoded).json")
    }
}
