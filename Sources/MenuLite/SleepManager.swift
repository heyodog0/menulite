// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import Foundation
import IOKit.pwr_mgt

/// Prevents idle sleep via an IOKit power assertion. No external process.
/// With `display` it uses the display assertion (like `caffeinate -d`): the
/// screen stays on, which also keeps the system from idle-sleeping. Without it,
/// only the Mac stays awake (like `caffeinate -i`) and the screen may still
/// turn off — right for a long job you don't need to watch.
final class SleepManager {
    private var assertionID: IOPMAssertionID = 0
    private var active = false

    func set(enabled: Bool, display: Bool) {
        disable()
        if enabled { enable(display: display) }
    }

    private func enable(display: Bool) {
        let type = display ? kIOPMAssertionTypePreventUserIdleDisplaySleep
                           : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
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
