import CaffeineCore
import Darwin
import Foundation
import IOKit.pwr_mgt

actor PowerAssertionScanner {
    func scan(excluding ownPID: Int32) -> [SleepBlocker] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dictionary = unmanaged?.takeRetainedValue() as NSDictionary?
        else { return [] }

        var records: [PowerAssertionRecord] = []
        for value in dictionary.allValues {
            guard let assertions = value as? [NSDictionary] else { continue }
            records.append(contentsOf: assertions.compactMap(self.record))
        }
        return SleepBlockerCatalog.blockers(from: records, excluding: ownPID)
    }

    private func record(from assertion: NSDictionary) -> PowerAssertionRecord? {
        guard let type = assertion["AssertType"] as? String,
              let kind = SleepAssertionKind(rawValue: type),
              let assertingPID = (assertion["AssertPID"] as? NSNumber)?.int32Value
        else { return nil }

        let assertingName = assertion["Process Name"] as? String
            ?? self.processName(for: assertingPID)
            ?? "PID \(assertingPID)"
        let onBehalfPID = (assertion["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value
        let resolvedOwnerName = onBehalfPID.flatMap(self.processName)
        let ownerPID = resolvedOwnerName == nil ? assertingPID : onBehalfPID ?? assertingPID
        let ownerName = resolvedOwnerName ?? assertingName
        let level = (assertion["AssertLevel"] as? NSNumber)?.intValue ?? 0

        return PowerAssertionRecord(
            assertingPID: assertingPID,
            ownerPID: ownerPID,
            processName: ownerName,
            assertingProcessName: assertingName,
            kind: kind,
            reason: self.reason(from: assertion),
            startedAt: assertion["AssertStartWhen"] as? Date,
            isActive: level > 0)
    }

    private func reason(from assertion: NSDictionary) -> String {
        if let resources = assertion["ResourcesUsed"] as? [String] {
            let input = resources.contains("audio-in")
            let output = resources.contains("audio-out")
            if input, output { return "Audio input and output" }
            if input { return "Audio input" }
            if output { return "Audio output" }
        }
        return assertion["Details"] as? String
            ?? assertion["HumanReadableReason"] as? String
            ?? assertion["AssertName"] as? String
            ?? "Power activity"
    }

    private func processName(for pid: Int32) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        if pathLength > 0,
           let path = String(
               bytes: pathBuffer.prefix(Int(pathLength)).map { UInt8(bitPattern: $0) },
               encoding: .utf8)
        {
            if let appComponent = path.split(separator: "/").first(where: { $0.hasSuffix(".app") }) {
                return String(appComponent.dropLast(4))
            }
        }

        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard nameLength > 0 else { return nil }
        return String(
            bytes: nameBuffer.prefix(Int(nameLength)).map { UInt8(bitPattern: $0) },
            encoding: .utf8)
    }
}
