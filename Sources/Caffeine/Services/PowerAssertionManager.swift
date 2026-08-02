import CaffeineCore
import Foundation
import IOKit.pwr_mgt

@MainActor
final class PowerAssertionManager {
    private var assertionIDs: [IOPMAssertionID] = []
    private var currentPlan: PowerAssertionPlan?

    deinit {
        for assertionID in self.assertionIDs {
            IOPMAssertionRelease(assertionID)
        }
    }

    func apply(_ plan: PowerAssertionPlan) -> String? {
        guard plan != self.currentPlan else { return nil }
        self.releaseAll()
        self.currentPlan = plan
        for assertion in plan.assertions {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                assertion.rawValue as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                assertion.reason as CFString,
                &assertionID)
            guard result == kIOReturnSuccess else {
                self.releaseAll()
                self.currentPlan = nil
                return "macOS rejected the power assertion (\(result))."
            }
            self.assertionIDs.append(assertionID)
        }
        return nil
    }

    func releaseAll() {
        for assertionID in self.assertionIDs {
            IOPMAssertionRelease(assertionID)
        }
        self.assertionIDs.removeAll()
    }
}
