import CaffeineCore

actor AgentLifecycleScanner {
    private let store = AgentLifecycleStore()

    func scan() -> [AgentLifecycleSession] {
        self.store.activeSessions()
    }
}
