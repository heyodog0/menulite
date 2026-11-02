// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import Foundation
import IOKit
import IOKit.ps

/// The internal battery, for Macs that have one: charge and time left from the
/// power-source API, plus power draw, health and cycle count from the battery's
/// own IORegistry entry (AppleSmartBattery). No permission needed.
enum BatteryMonitor {
    struct Reading: Equatable {
        var percent: Int
        var charging: Bool
        var pluggedIn: Bool
        /// Minutes to empty (on battery) or to full (charging); nil while macOS
        /// is still estimating.
        var minutesLeft: Int?
        /// Watts flowing out of (on battery) or into (charging) the battery.
        var watts: Double?
        /// Today's full capacity as a share of the design capacity.
        var healthPercent: Int?
        var cycles: Int?
    }

    /// nil on Macs without a battery.
    static func read() -> Reading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutes = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int
            var r = Reading(percent: current * 100 / max, charging: charging, pluggedIn: plugged,
                            minutesLeft: minutes.flatMap { $0 > 0 ? $0 : nil })
            readSmartBattery(into: &r)
            return r
        }
        return nil
    }

    private static func readSmartBattery(into r: inout Reading) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let p = props?.takeRetainedValue() as? [String: Any] else { return }

        r.cycles = p["CycleCount"] as? Int
        // Apple Silicon reports mAh in AppleRawMaxCapacity (MaxCapacity is a %).
        if let design = p["DesignCapacity"] as? Int, design > 0,
           let full = (p["AppleRawMaxCapacity"] ?? p["NominalChargeCapacity"]) as? Int {
            r.healthPercent = min(100, Int((Double(full) / Double(design) * 100).rounded()))
        }
        // Amperage is signed mA (negative while discharging), voltage mV.
        if let amps = (p["InstantAmperage"] ?? p["Amperage"]) as? Int,
           let volts = p["Voltage"] as? Int {
            let a = Int64(truncatingIfNeeded: amps)
            let w = abs(Double(a)) * Double(volts) / 1_000_000
            r.watts = w >= 0.1 ? w : nil
        }
    }
}
