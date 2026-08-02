import Foundation
import Testing
@testable import CaffeineCore

struct AwakePolicyTests {
    @Test func `manual sessions expire at their deadline`() {
        let now = Date(timeIntervalSince1970: 1000)
        let active = self.policy(manualActive: true, deadline: now.addingTimeInterval(60)).result(at: now)
        let expired = self.policy(manualActive: true, deadline: now).result(at: now)

        #expect(active.shouldStayAwake)
        #expect(active.remainingSeconds == 60)
        #expect(!expired.shouldStayAwake)
    }

    @Test func `agent watch activates for a matching process`() {
        let agent = RunningAgent(pid: 42, executable: "codex", label: "Codex")
        let result = self.policy(agentWatch: true, agents: [agent]).result()

        #expect(result.shouldStayAwake)
        #expect(result.source == .agents(["Codex"]))
    }

    @Test func `battery cutoff pauses requested sessions only on battery`() {
        let paused = self.policy(manualActive: true, battery: 10, onBattery: true, cutoff: 15).result()
        let pluggedIn = self.policy(manualActive: true, battery: 10, onBattery: false, cutoff: 15).result()

        #expect(paused == AwakePolicyResult(
            shouldStayAwake: false,
            source: .batteryPaused(percent: 10),
            remainingSeconds: nil))
        #expect(pluggedIn.shouldStayAwake)
    }

    @Test func `process parser finds direct and wrapped agent commands`() {
        let output = """
          101 /opt/homebrew/bin/codex codex exec --full-auto
          102 /usr/bin/env env claude --print
          103 /usr/bin/swift swift build
        """
        let agents = ProcessListParser.agents(in: output, signatures: AgentSignature.defaults)

        #expect(agents.map(\.pid) == [102, 101])
        #expect(Set(agents.map(\.executable)) == ["codex", "claude"])
    }

    @Test func `process parser ignores desktop app helpers and persistent hosts`() {
        let output = """
          201 /Applications/Claude.app/Contents/MacOS/Claude /Applications/Claude.app/Contents/MacOS/Claude
          202 /Applications/ChatGPT.app/Contents/Resources/codex codex app-server
          203 /Users/me/.local/bin/codex codex --yolo
        """
        let agents = ProcessListParser.agents(in: output, signatures: AgentSignature.defaults)

        #expect(agents.map(\.pid) == [203])
    }

    @Test func `process parser ignores truncated desktop app commands`() {
        let output = """
          201 /Applications/Cl /Applications/Claude.app/Contents/MacOS/Claude
          202 /Applications/Cl /Applications/Claude Helper.app/Contents/MacOS/Claude Helper
          203 /Users/me/.local/bin/claude claude --plugin-dir /Applications/Conductor.app/Contents/Resources
        """
        let agents = ProcessListParser.agents(in: output, signatures: AgentSignature.defaults)

        #expect(agents.map(\.pid) == [203])
    }

    @Test func `process fallback includes main apps but not their helpers`() {
        let output = """
          201 /Applications/Cl /Applications/Claude.app/Contents/MacOS/Claude
          202 /Applications/Cl /Applications/Claude Helper.app/Contents/MacOS/Claude Helper
          203 /Users/me/.local/bin/claude claude
        """
        let agents = ProcessListParser.agents(
            in: output,
            signatures: AgentSignature.defaults,
            includeAppBundles: true)

        #expect(agents.map(\.pid) == [201, 203])
    }

    @Test(arguments: [
        ("30", 1800.0),
        ("45m", 2700.0),
        ("2h", 7200.0),
        ("1d", 86400.0),
        ("forever", 0.0),
    ])
    func `duration parser accepts friendly values`(input: String, expected: Double) {
        #expect(DurationParser.seconds(from: input) == expected)
    }

    @Test func `default active plan keeps the system display and network awake`() {
        let plan = PowerAssertionPlan(
            active: true,
            allowDisplaySleep: false,
            keepNetworkActive: true,
            closedLidMode: false)

        #expect(plan.assertions == [.system, .network, .display])
    }

    @Test func `power settings change the assertion plan`() {
        let unattended = PowerAssertionPlan(
            active: true,
            allowDisplaySleep: true,
            keepNetworkActive: false,
            closedLidMode: true)
        let inactive = PowerAssertionPlan(
            active: false,
            allowDisplaySleep: false,
            keepNetworkActive: true,
            closedLidMode: true)

        #expect(unattended.assertions == [.system, .closedLid])
        #expect(inactive.assertions.isEmpty)
    }

    @Test func `sleep blockers group assertions by owning process`() {
        let now = Date(timeIntervalSince1970: 1000)
        let records = [
            self.assertion(pid: 99, process: "Caffeine", reason: "Caffeine", kind: .systemIdle),
            self.assertion(pid: 98, process: "Caffeine", reason: "Old Caffeine", kind: .systemIdle),
            self.assertion(
                pid: 1,
                process: "powerd",
                reason: "Powerd - Prevent sleep while display is on",
                kind: .systemIdle),
            self.assertion(pid: 10, process: "caffeinate", reason: "asserting forever", kind: .systemIdle),
            PowerAssertionRecord(
                assertingPID: 20,
                ownerPID: 30,
                processName: "Dictation",
                assertingProcessName: "coreaudiod",
                kind: .systemIdle,
                reason: "Audio input",
                startedAt: now,
                isActive: true),
            PowerAssertionRecord(
                assertingPID: 20,
                ownerPID: 30,
                processName: "Dictation",
                assertingProcessName: "coreaudiod",
                kind: .displayIdle,
                reason: "Video call",
                startedAt: now,
                isActive: true),
            PowerAssertionRecord(
                assertingPID: 40,
                ownerPID: 40,
                processName: "finished",
                assertingProcessName: "finished",
                kind: .systemIdle,
                reason: "Inactive",
                startedAt: now,
                isActive: false),
        ]

        let blockers = SleepBlockerCatalog.blockers(from: records, excluding: 99)

        #expect(blockers.map(\.processName) == ["caffeinate", "Dictation"])
        #expect(blockers[0].assertions.map(\.kind) == [.systemIdle])
        #expect(blockers[1].viaProcessName == "coreaudiod")
        #expect(Set(blockers[1].assertions.map(\.kind)) == [.systemIdle, .displayIdle])
    }

    private func policy(
        manualActive: Bool = false,
        deadline: Date? = nil,
        agentWatch: Bool = false,
        agents: [RunningAgent] = [],
        battery: Int? = nil,
        onBattery: Bool = false,
        cutoff: Int = 15) -> AwakePolicy
    {
        AwakePolicy(
            manualActive: manualActive,
            manualDeadline: deadline,
            agentWatchEnabled: agentWatch,
            smartPaused: false,
            activeAgents: agents.map(ActiveAgent.init(process:)),
            batteryPercent: battery,
            isOnBattery: onBattery,
            batteryCutoff: cutoff)
    }

    private func assertion(
        pid: Int32,
        process: String,
        reason: String,
        kind: SleepAssertionKind) -> PowerAssertionRecord
    {
        PowerAssertionRecord(
            assertingPID: pid,
            ownerPID: pid,
            processName: process,
            assertingProcessName: process,
            kind: kind,
            reason: reason,
            startedAt: nil,
            isActive: true)
    }
}
