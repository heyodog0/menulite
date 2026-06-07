import Foundation
import IOKit.pwr_mgt

/// Prevents idle sleep via an IOKit power assertion. No external process.
/// Uses the *display* assertion (like `caffeinate -d`): keeping the display
/// awake also keeps the system from idle-sleeping. The system-only assertion
/// (PreventUserIdleSystemSleep) leaves the display free to sleep, so the screen
/// still goes black and it looks like nothing was prevented.
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
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
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
