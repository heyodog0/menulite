// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

import AppKit
import SwiftUI
import ApplicationServices

// The CGEventTap callback must be a non-capturing C function, so the tap port
// lives at file scope to allow re-enabling it after a system timeout.
private var gKeyboardTap: CFMachPort?

private func keyboardSwallow(proxy: CGEventTapProxy, type: CGEventType,
                             event: CGEvent, userInfo: UnsafeMutableRawPointer?)
    -> Unmanaged<CGEvent>? {
    // macOS may disable the tap; re-enable and let that control event pass.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = gKeyboardTap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    // Swallow every keyboard event so you can wipe the keys safely.
    return nil
}

/// "Keyboard cleaning" mode: disables the keyboard and shows an overlay with a
/// mouse-clickable Done button. Requires Accessibility permission.
@MainActor
final class KeyboardCleaner {
    private var runLoopSource: CFRunLoopSource?
    private var overlay: NSWindow?
    private var armTimer: Timer?
    private let onEnd: () -> Void

    init(onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
    }

    enum StartError: Error {
        /// No Accessibility grant (the system prompt has just been shown).
        case notTrusted
        /// Trusted, but the event tap was refused — typically a grant made after
        /// this process launched, which macOS doesn't apply until a relaunch.
        case tapRefused
    }

    func start() throws {
        guard ensureAccessibility() else { throw StartError.notTrusted }

        let mask: CGEventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.keyUp.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: keyboardSwallow, userInfo: nil) else { throw StartError.tapRefused }

        gKeyboardTap = tap
        CGEvent.tapEnable(tap: tap, enable: false)
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        runLoopSource = src

        showOverlay()
        // Lock only once every key is up. Started from ⌃⌥K, the keys are still
        // held; swallowing their key-ups would leave macOS thinking K is down,
        // so the next ⌃⌥K would take two presses.
        armTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard !Self.anyKeyHeld() else { return }
                t.invalidate()
                self?.armTimer = nil
                if let tap = gKeyboardTap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
        }
    }

    private static func anyKeyHeld() -> Bool {
        let mods: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        if !CGEventSource.flagsState(.combinedSessionState).intersection(mods).isEmpty { return true }
        // Caps Lock (57) can read as held while it is merely on.
        return (0..<128).contains { $0 != 57 && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) }
    }

    func stop() {
        armTimer?.invalidate()
        armTimer = nil
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let tap = gKeyboardTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            gKeyboardTap = nil
        }
        overlay?.orderOut(nil)
        overlay = nil
    }

    // MARK: - permission + overlay
    private func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func showOverlay() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let w = NSWindow(contentRect: frame, styleMask: .borderless,
                         backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = NSColor.black.withAlphaComponent(0.82)
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.ignoresMouseEvents = false   // we still want the Done button clickable
        let root = CleaningOverlay { [weak self] in
            self?.stop()
            self?.onEnd()
        }
        w.contentView = NSHostingView(rootView: root)
        w.setFrame(frame, display: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        overlay = w
    }
}

/// A small, quiet cat glyph: the keyboard lock doubles as catproofing (paws on
/// the keys can't type either). Drawn like the panel's other secondary icons.
struct CatproofBadge: View {
    var size: CGFloat
    var body: some View {
        Image(systemName: "cat")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(.secondary)
            .help("Also catproof — paws can’t type while it’s on")
    }
}

private struct CleaningOverlay: View {
    let onDone: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            // The cat sits quietly by the keyboard it can no longer type on.
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 56, weight: .thin))
                CatproofBadge(size: 22)
            }
            Text("Keyboard cleaning")
                .font(.system(size: 26, weight: .semibold))
            Text("Your keyboard is disabled — wipe away (or let the cat walk).\nThe mouse still works.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 28).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)   // harmless; keys are swallowed anyway
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}
