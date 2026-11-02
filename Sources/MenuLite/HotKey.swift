// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon's hot-key API delivers just the
/// registered combination to us — it isn't a keyboard monitor, so it needs no
/// Accessibility or Input Monitoring grant.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void
    private static var nextID: UInt32 = 1

    /// nil if the combination couldn't be registered (another app owns it).
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.id = Self.nextID
        Self.nextID += 1
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // Every hot key's handler sees every press, so each checks the id.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.id == me.id else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D_4C_49_54), id: id)   // "MLIT"
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                  GetApplicationEventTarget(), 0, &ref) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
