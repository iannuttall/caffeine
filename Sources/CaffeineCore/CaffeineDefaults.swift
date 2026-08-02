import Foundation

public enum CaffeineDefaults {
    public static let suiteName = "com.iannuttall.caffeine.shared"
    public static let commandNotification = Notification.Name("com.iannuttall.caffeine.command")

    public enum Key {
        public static let manualActive = "manualActive"
        public static let manualDeadline = "manualDeadline"
        public static let command = "pendingCommand"
        public static let commandDuration = "pendingCommandDuration"
        public static let commandRevision = "commandRevision"
        public static let commandHandledRevision = "commandHandledRevision"
        public static let statusActive = "statusActive"
        public static let statusSource = "statusSource"
        public static let statusAgents = "statusAgents"
        public static let statusInstalledAgents = "statusInstalledAgents"
        public static let statusBattery = "statusBattery"
        public static let statusUpdatedAt = "statusUpdatedAt"
    }
}

public enum CaffeineCommand: String, Codable, Sendable {
    case activate
    case deactivate
    case toggle
}
