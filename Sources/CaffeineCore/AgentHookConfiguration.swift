import Foundation

public enum AgentHookTarget: String, CaseIterable, Sendable {
    case claude
    case codex
}

public enum AgentHookConfiguration {
    public static let commandMarker = "CAFFEINE_LIFECYCLE_HOOK=1"

    public static func installing(
        in data: Data?,
        target: AgentHookTarget,
        command: (AgentLifecycleAction, AgentLifecycleProvider) -> String) throws -> Data
    {
        var root = try self.rootObject(from: data)
        var hooks = try self.hooksObject(from: root)
        self.removeOwnedHandlers(from: &hooks)

        let provider: AgentLifecycleProvider = target == .claude ? .claude : .codex
        self.append(command(.start, provider), to: "UserPromptSubmit", in: &hooks)

        for event in ["PreToolUse", "PostToolUse", "PreCompact", "PostCompact", "SubagentStart"] {
            self.append(command(.refresh, provider), to: event, in: &hooks, matcher: self.toolMatcher(for: event))
        }

        self.append(command(.wait, provider), to: "PermissionRequest", in: &hooks, matcher: "*")
        self.append(command(.stop, provider), to: "Stop", in: &hooks)
        self.append(
            command(.stop, provider),
            to: "SessionEnd",
            in: &hooks,
            timeout: target == .codex ? 3 : 5)

        if target == .claude {
            self.append(command(.refresh, provider), to: "PostToolUseFailure", in: &hooks, matcher: "*")
            self.append(command(.refresh, provider), to: "PermissionDenied", in: &hooks, matcher: "*")
            self.append(
                command(.wait, provider),
                to: "Notification",
                in: &hooks,
                matcher: "permission_prompt|idle_prompt|agent_needs_input")
            self.append(command(.wait, provider), to: "Elicitation", in: &hooks, matcher: "*")
            self.append(command(.refresh, provider), to: "ElicitationResult", in: &hooks, matcher: "*")
            self.append(command(.stop, provider), to: "StopFailure", in: &hooks, matcher: "*")
        }

        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public static func removing(from data: Data?) throws -> Data? {
        guard data != nil else { return nil }
        var root = try self.rootObject(from: data)
        var hooks = try self.hooksObject(from: root)
        self.removeOwnedHandlers(from: &hooks)
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public static func containsInstalledHooks(in data: Data?, target: AgentHookTarget) -> Bool {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any]
        else { return false }
        let commonEvents = [
            "PermissionRequest",
            "PostCompact",
            "PostToolUse",
            "PreCompact",
            "PreToolUse",
            "SessionEnd",
            "Stop",
            "SubagentStart",
            "UserPromptSubmit",
        ]
        let claudeEvents = [
            "Elicitation",
            "ElicitationResult",
            "Notification",
            "PermissionDenied",
            "PostToolUseFailure",
            "StopFailure",
        ]
        let requiredEvents = target == .claude ? commonEvents + claudeEvents : commonEvents
        return requiredEvents.allSatisfy { event in
            guard let handlers = hooks[event] else { return false }
            return self.containsMarker(handlers)
        }
    }

    private static func rootObject(from data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentHookConfigurationError.invalidRoot
        }
        return root
    }

    private static func hooksObject(from root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else {
            throw AgentHookConfigurationError.invalidHooks
        }
        for (event, groups) in hooks where groups as? [[String: Any]] == nil {
            throw AgentHookConfigurationError.invalidEvent(event)
        }
        return hooks
    }

    private static func append(
        _ command: String,
        to event: String,
        in hooks: inout [String: Any],
        matcher: String? = nil,
        timeout: Int = 5)
    {
        var groups = hooks[event] as? [[String: Any]] ?? []
        var group: [String: Any] = [
            "hooks": [[
                "command": command,
                "timeout": timeout,
                "type": "command",
            ]],
        ]
        if let matcher { group["matcher"] = matcher }
        groups.append(group)
        hooks[event] = groups
    }

    private static func removeOwnedHandlers(from hooks: inout [String: Any]) {
        for event in Array(hooks.keys) {
            guard let groups = hooks[event] as? [[String: Any]] else { continue }
            let cleaned = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = handlers.filter { !self.containsMarker($0) }
                guard !remaining.isEmpty else { return nil }
                var updated = group
                updated["hooks"] = remaining
                return updated
            }
            if cleaned.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = cleaned
            }
        }
    }

    private static func containsMarker(_ value: Any) -> Bool {
        if let string = value as? String { return string.contains(self.commandMarker) }
        if let array = value as? [Any] { return array.contains(where: self.containsMarker) }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: self.containsMarker)
        }
        return false
    }

    private static func toolMatcher(for event: String) -> String? {
        ["PreToolUse", "PostToolUse"].contains(event) ? "*" : nil
    }
}

public enum AgentHookConfigurationError: LocalizedError {
    case invalidEvent(String)
    case invalidHooks
    case invalidRoot

    public var errorDescription: String? {
        switch self {
        case let .invalidEvent(event): "The existing \(event) hook has an unsupported structure."
        case .invalidHooks: "The existing hooks setting has an unsupported structure."
        case .invalidRoot: "The hook configuration must contain a JSON object."
        }
    }
}
