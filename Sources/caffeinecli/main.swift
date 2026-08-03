import CaffeineCore
import Foundation

@main
enum CaffeineCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let defaults = UserDefaults(suiteName: CaffeineDefaults.suiteName) ?? .standard

        guard let command = arguments.first else {
            self.usage()
            Foundation.exit(2)
        }

        switch command {
        case "status":
            self.status(defaults: defaults, json: arguments.contains("--json"))
        case "on":
            self.send(.activate, duration: nil, defaults: defaults)
        case "off":
            self.send(.deactivate, duration: nil, defaults: defaults)
        case "toggle":
            self.send(.toggle, duration: nil, defaults: defaults)
        case "for":
            guard arguments.count >= 2, let duration = DurationParser.seconds(from: arguments[1]) else {
                FileHandle.standardError.write(Data("Usage: caffeine for <30m|2h|1d>\n".utf8))
                Foundation.exit(2)
            }
            self.send(.activate, duration: duration, defaults: defaults)
        case "agent-event":
            self.agentEvent(arguments: Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            self.usage()
        default:
            FileHandle.standardError.write(Data("Unknown command: \(command)\n".utf8))
            self.usage()
            Foundation.exit(2)
        }
    }

    private static func send(_ command: CaffeineCommand, duration: TimeInterval?, defaults: UserDefaults) {
        defaults.set(command.rawValue, forKey: CaffeineDefaults.Key.command)
        defaults.set(duration, forKey: CaffeineDefaults.Key.commandDuration)
        defaults.set(UUID().uuidString, forKey: CaffeineDefaults.Key.commandRevision)
        defaults.synchronize()
        #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(
            CaffeineDefaults.commandNotification,
            object: nil,
            deliverImmediately: true)
        #endif
        print(command == .deactivate ? "Caffeine is resting." : "Caffeine command sent.")
    }

    private static func status(defaults: UserDefaults, json: Bool) {
        let active = defaults.bool(forKey: CaffeineDefaults.Key.statusActive)
        let source = defaults.string(forKey: CaffeineDefaults.Key.statusSource) ?? "App is not running"
        let agents = defaults.stringArray(forKey: CaffeineDefaults.Key.statusAgents) ?? []
        let installedAgents = defaults.stringArray(forKey: CaffeineDefaults.Key.statusInstalledAgents) ?? []
        let batteryValue = defaults.object(forKey: CaffeineDefaults.Key.statusBattery) as? Int
        let updatedAt = defaults.object(forKey: CaffeineDefaults.Key.statusUpdatedAt) as? Date

        if json {
            let value: [String: Any] = [
                "active": active,
                "source": source,
                "agents": agents,
                "installedAgents": installedAgents,
                "batteryPercent": batteryValue ?? NSNull(),
                "updatedAt": updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            ]
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            print(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
            return
        }

        print(active ? "active" : "inactive")
        print(source)
        if !agents.isEmpty { print("Agents: \(agents.joined(separator: ", "))") }
        if !installedAgents.isEmpty { print("Installed: \(installedAgents.joined(separator: ", "))") }
        if let batteryValue { print("Battery: \(batteryValue)%") }
    }

    private static func agentEvent(arguments: [String]) {
        guard arguments.count == 2,
              let action = AgentLifecycleAction(rawValue: arguments[0]),
              let provider = AgentLifecycleProvider(rawValue: arguments[1])
        else { return }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = try? AgentHookPayload(data: data) else { return }
        try? AgentLifecycleStore().apply(action: action, provider: provider, payload: payload)
    }

    private static func usage() {
        print("""
        Usage: caffeine <command>

          status [--json]   Show the app's last reported state
          on                Keep the Mac awake indefinitely
          off               Release the manual awake session
          toggle            Toggle the manual session
          for <duration>    Stay awake for 30m, 2h, or 1d
        """)
    }
}
