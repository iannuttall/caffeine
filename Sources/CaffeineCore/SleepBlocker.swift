import Foundation

public enum SleepAssertionKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case systemIdle = "PreventUserIdleSystemSleep"
    case displayIdle = "PreventUserIdleDisplaySleep"
    case system = "PreventSystemSleep"
    case network = "NetworkClientActive"
    case legacySystem = "NoIdleSleepAssertion"
    case legacyDisplay = "NoDisplaySleepAssertion"

    public var label: String {
        switch self {
        case .systemIdle, .legacySystem: "Mac awake"
        case .displayIdle, .legacyDisplay: "Display awake"
        case .system: "System sleep blocked"
        case .network: "Network active"
        }
    }
}

public struct PowerAssertionRecord: Equatable, Sendable {
    public let assertingPID: Int32
    public let ownerPID: Int32
    public let processName: String
    public let assertingProcessName: String
    public let kind: SleepAssertionKind
    public let reason: String
    public let startedAt: Date?
    public let isActive: Bool

    public init(
        assertingPID: Int32,
        ownerPID: Int32,
        processName: String,
        assertingProcessName: String,
        kind: SleepAssertionKind,
        reason: String,
        startedAt: Date?,
        isActive: Bool)
    {
        self.assertingPID = assertingPID
        self.ownerPID = ownerPID
        self.processName = processName
        self.assertingProcessName = assertingProcessName
        self.kind = kind
        self.reason = reason
        self.startedAt = startedAt
        self.isActive = isActive
    }
}

public struct SleepBlockerAssertion: Equatable, Sendable {
    public let kind: SleepAssertionKind
    public let reason: String
    public let startedAt: Date?

    public init(kind: SleepAssertionKind, reason: String, startedAt: Date?) {
        self.kind = kind
        self.reason = reason
        self.startedAt = startedAt
    }
}

public struct SleepBlocker: Equatable, Identifiable, Sendable {
    public let pid: Int32
    public let processName: String
    public let viaProcessName: String?
    public let assertions: [SleepBlockerAssertion]

    public var id: Int32 {
        self.pid
    }

    public init(
        pid: Int32,
        processName: String,
        viaProcessName: String?,
        assertions: [SleepBlockerAssertion])
    {
        self.pid = pid
        self.processName = processName
        self.viaProcessName = viaProcessName
        self.assertions = assertions
    }
}

public enum SleepBlockerCatalog {
    public static func blockers(
        from records: [PowerAssertionRecord],
        excluding ownPID: Int32,
        ownProcessName: String = "Caffeine") -> [SleepBlocker]
    {
        let visible = records.filter { record in
            record.isActive
                && record.assertingPID != ownPID
                && record.assertingProcessName.caseInsensitiveCompare(ownProcessName) != .orderedSame
                && !(record.assertingProcessName == "powerd"
                    && record.reason == "Powerd - Prevent sleep while display is on")
        }

        return Dictionary(grouping: visible, by: \.ownerPID)
            .compactMap { pid, group -> SleepBlocker? in
                guard let first = group.first else { return nil }
                let assertions = group
                    .map { SleepBlockerAssertion(kind: $0.kind, reason: $0.reason, startedAt: $0.startedAt) }
                    .sorted {
                        if $0.kind.rawValue == $1.kind.rawValue {
                            return $0.reason < $1.reason
                        }
                        return $0.kind.rawValue < $1.kind.rawValue
                    }
                let viaNames = Set(group.compactMap { record in
                    record.assertingPID == record.ownerPID ? nil : record.assertingProcessName
                })
                return SleepBlocker(
                    pid: pid,
                    processName: first.processName,
                    viaProcessName: viaNames.count == 1 ? viaNames.first : nil,
                    assertions: assertions)
            }
            .sorted {
                let order = $0.processName.localizedCaseInsensitiveCompare($1.processName)
                return order == .orderedSame ? $0.pid < $1.pid : order == .orderedAscending
            }
    }
}
