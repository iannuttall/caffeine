import Foundation
import Testing
@testable import CaffeineCore

struct AgentLifecycleTests {
    @Test func `hook installation preserves existing settings and is idempotent`() throws {
        let original = Data("""
        {
          "theme": "dark",
          "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "echo existing"}]}]
          }
        }
        """.utf8)
        let command: (AgentLifecycleAction, AgentLifecycleProvider) -> String = { action, provider in
            "\(AgentHookConfiguration.commandMarker) caffeine \(action.rawValue) \(provider.rawValue)"
        }

        let installed = try AgentHookConfiguration.installing(in: original, target: .codex, command: command)
        let reinstalled = try AgentHookConfiguration.installing(in: installed, target: .codex, command: command)
        let text = try #require(String(data: reinstalled, encoding: .utf8))

        #expect(text.contains("echo existing"))
        #expect(text.contains("\"theme\" : \"dark\""))
        #expect(self.markerCount(in: reinstalled) == self.markerCount(in: installed))
        #expect(AgentHookConfiguration.containsInstalledHooks(in: reinstalled, target: .codex))
        #expect(!AgentHookConfiguration.containsInstalledHooks(in: reinstalled, target: .claude))
        #expect(!text.contains("Notification"))
        #expect(!text.contains("PostToolUseFailure"))

        let removalResult = try AgentHookConfiguration.removing(from: reinstalled)
        let removed = try #require(removalResult)
        let removedText = try #require(String(data: removed, encoding: .utf8))
        #expect(removedText.contains("echo existing"))
        #expect(removedText.contains("\"theme\" : \"dark\""))
        #expect(!removedText.contains(AgentHookConfiguration.commandMarker))
        #expect(!AgentHookConfiguration.containsInstalledHooks(in: removed, target: .codex))
    }

    @Test func `Claude hooks include input waiting events`() throws {
        let installed = try AgentHookConfiguration.installing(in: nil, target: .claude) { action, provider in
            "\(AgentHookConfiguration.commandMarker) caffeine \(action.rawValue) \(provider.rawValue)"
        }
        let text = try #require(String(data: installed, encoding: .utf8))

        #expect(text.contains("Notification"))
        #expect(text.contains("agent_needs_input"))
        #expect(text.contains("PermissionRequest"))
        #expect(text.contains("StopFailure"))
    }

    @Test func `hook editing rejects unfamiliar structures`() {
        let invalidHooks = Data(#"{"hooks":"leave this alone"}"#.utf8)
        let invalidEvent = Data(#"{"hooks":{"Stop":"leave this alone"}}"#.utf8)
        let command: (AgentLifecycleAction, AgentLifecycleProvider) -> String = { _, _ in "caffeine" }

        #expect(throws: AgentHookConfigurationError.self) {
            try AgentHookConfiguration.installing(in: invalidHooks, target: .codex, command: command)
        }
        #expect(throws: AgentHookConfigurationError.self) {
            try AgentHookConfiguration.installing(in: invalidEvent, target: .codex, command: command)
        }
        #expect(throws: AgentHookConfigurationError.self) {
            try AgentHookConfiguration.removing(from: invalidHooks)
        }
    }

    @Test func `lifecycle store starts waits and expires sessions`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("caffeine-lifecycle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AgentLifecycleStore(directory: directory)
        let payload = AgentHookPayload(sessionID: "session/one")
        let now = Date(timeIntervalSince1970: 10000)

        try store.apply(action: .start, provider: .claude, payload: payload, at: now)
        #expect(store.activeSessions(at: now).map(\.sessionID) == ["session/one"])
        #expect(store.activeSessions(at: now.addingTimeInterval(4 * 60 * 60)).map(\.sessionID) == ["session/one"])

        try store.apply(action: .wait, provider: .claude, payload: payload, at: now)
        #expect(store.activeSessions(at: now).isEmpty)

        try store.apply(
            action: .start,
            provider: .codex,
            payload: payload,
            at: now.addingTimeInterval(-AgentLifecycleStore.staleInterval))
        #expect(store.activeSessions(at: now).isEmpty)
    }

    @Test func `hook payload reads the shared session identifier`() throws {
        let payload = try AgentHookPayload(data: Data(#"{"session_id":"abc-123","cwd":"/tmp"}"#.utf8))

        #expect(payload.sessionID == "abc-123")
    }

    private func markerCount(in data: Data) -> Int {
        guard let text = String(data: data, encoding: .utf8) else { return 0 }
        return text.components(separatedBy: AgentHookConfiguration.commandMarker).count - 1
    }
}
