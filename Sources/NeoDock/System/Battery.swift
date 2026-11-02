import Foundation
import IOKit.ps

struct BatteryStatus: Equatable {
    let percent: Int
    let isCharging: Bool
}

enum Battery {
    /// nil auf Macs ohne internen Akku.
    static func read() -> BatteryStatus? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatteryStatus(percent: current * 100 / maximum, isCharging: info[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }
}
