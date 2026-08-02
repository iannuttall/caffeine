import CaffeineCore
import Foundation

struct AgentHookInstallStatus: Equatable {
    let claudeInstalled: Bool
    let codexInstalled: Bool

    var allInstalled: Bool {
        self.claudeInstalled && self.codexInstalled
    }

    var anyInstalled: Bool {
        self.claudeInstalled || self.codexInstalled
    }
}

struct AgentHookInstaller {
    let homeDirectory: URL
    let cliURL: URL

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        cliURL: URL = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("caffeinecli") ?? URL(fileURLWithPath: "/usr/local/bin/caffeinecli"))
    {
        self.homeDirectory = homeDirectory
        self.cliURL = cliURL
    }

    var status: AgentHookInstallStatus {
        AgentHookInstallStatus(
            claudeInstalled: AgentHookConfiguration.containsInstalledHooks(
                in: try? self.read(self.claudeURL),
                target: .claude),
            codexInstalled: AgentHookConfiguration.containsInstalledHooks(
                in: try? self.read(self.codexURL),
                target: .codex))
    }

    func install() throws -> AgentHookInstallStatus {
        guard FileManager.default.isExecutableFile(atPath: self.cliURL.path) else {
            throw AgentHookInstallError.missingCLI
        }

        let claudeOriginal = try self.read(self.claudeURL)
        let codexOriginal = try self.read(self.codexURL)
        let claude = try AgentHookConfiguration.installing(
            in: claudeOriginal,
            target: .claude,
            command: self.command)
        let codex = try AgentHookConfiguration.installing(
            in: codexOriginal,
            target: .codex,
            command: self.command)

        try self.write(claude, to: self.claudeURL, replacing: claudeOriginal)
        do {
            try self.write(codex, to: self.codexURL, replacing: codexOriginal)
        } catch {
            try? self.restore(claudeOriginal, at: self.claudeURL, replacing: claude)
            throw error
        }
        return self.status
    }

    func remove() throws -> AgentHookInstallStatus {
        let claudeOriginal = try self.read(self.claudeURL)
        let codexOriginal = try self.read(self.codexURL)
        let claude = try AgentHookConfiguration.removing(from: claudeOriginal)
        let codex = try AgentHookConfiguration.removing(from: codexOriginal)

        if let claude { try self.write(claude, to: self.claudeURL, replacing: claudeOriginal) }
        do {
            if let codex { try self.write(codex, to: self.codexURL, replacing: codexOriginal) }
        } catch {
            if let claude {
                try? self.restore(claudeOriginal, at: self.claudeURL, replacing: claude)
            }
            throw error
        }
        AgentLifecycleStore().removeAll()
        return self.status
    }

    private var claudeURL: URL {
        self.homeDirectory.appendingPathComponent(".claude/settings.json")
    }

    private var codexURL: URL {
        self.homeDirectory.appendingPathComponent(".codex/hooks.json")
    }

    private func command(action: AgentLifecycleAction, provider: AgentLifecycleProvider) -> String {
        let quotedPath = "'\(self.cliURL.path.replacingOccurrences(of: "'", with: "'\\''"))'"
        let event = "agent-event \(action.rawValue) \(provider.rawValue)"
        return "\(AgentHookConfiguration.commandMarker) \(quotedPath) \(event)"
    }

    private func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func write(_ data: Data, to url: URL, replacing original: Data?) throws {
        guard try self.read(url) == original else {
            throw AgentHookInstallError.configurationChanged(url)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func restore(_ data: Data?, at url: URL, replacing replacement: Data) throws {
        guard try self.read(url) == replacement else { return }
        if let data {
            try self.write(data, to: url, replacing: replacement)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

private enum AgentHookInstallError: LocalizedError {
    case configurationChanged(URL)
    case missingCLI

    var errorDescription: String? {
        switch self {
        case let .configurationChanged(url):
            "\(url.lastPathComponent) changed while Caffeine was editing it. Nothing else was overwritten."
        case .missingCLI: "This app bundle does not contain the Caffeine command-line helper."
        }
    }
}
