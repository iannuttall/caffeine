import Foundation
import IOKit.ps

struct PowerSourceState: Equatable {
    let batteryPercent: Int?
    let isOnBattery: Bool
}

enum PowerSourceMonitor {
    static func current() -> PowerSourceState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSourceState(batteryPercent: nil, isOnBattery: false)
        }

        let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        let isOnBattery = sourceType == kIOPSBatteryPowerValue
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerSourceState(batteryPercent: nil, isOnBattery: isOnBattery)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0
            else { continue }
            return PowerSourceState(
                batteryPercent: Int((Double(current) / Double(maximum) * 100).rounded()),
                isOnBattery: isOnBattery)
        }

        return PowerSourceState(batteryPercent: nil, isOnBattery: isOnBattery)
    }
}
