public enum PowerAssertionKind: String, CaseIterable, Equatable, Sendable {
    case system = "PreventUserIdleSystemSleep"
    case display = "PreventUserIdleDisplaySleep"
    case network = "NetworkClientActive"
    case closedLid = "PreventSystemSleep"

    public var reason: String {
        switch self {
        case .system: "Caffeine is keeping this Mac awake"
        case .display: "Caffeine is keeping the display awake"
        case .network: "Caffeine is keeping network sessions active"
        case .closedLid: "Caffeine closed-lid mode"
        }
    }
}

public struct PowerAssertionPlan: Equatable, Sendable {
    public let active: Bool
    public let allowDisplaySleep: Bool
    public let keepNetworkActive: Bool
    public let closedLidMode: Bool

    public init(
        active: Bool,
        allowDisplaySleep: Bool,
        keepNetworkActive: Bool,
        closedLidMode: Bool)
    {
        self.active = active
        self.allowDisplaySleep = allowDisplaySleep
        self.keepNetworkActive = keepNetworkActive
        self.closedLidMode = closedLidMode
    }

    public var assertions: [PowerAssertionKind] {
        guard self.active else { return [] }

        var assertions: [PowerAssertionKind] = [.system]
        if self.keepNetworkActive { assertions.append(.network) }
        if !self.allowDisplaySleep { assertions.append(.display) }
        if self.closedLidMode { assertions.append(.closedLid) }
        return assertions
    }
}
