import Foundation
import IOKit.pwr_mgt

/// Prevents idle sleep via an IOKit power assertion. No external process.
final class SleepManager {
    private var assertionID: IOPMAssertionID = 0
    private var active = false

    func setEnabled(_ on: Bool) {
        if on { enable() } else { disable() }
    }

    private func enable() {
        guard !active else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "MenuLite: keep awake" as CFString,
            &id)
        if result == kIOReturnSuccess {
            assertionID = id
            active = true
        }
    }

    private func disable() {
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        active = false
    }
}
