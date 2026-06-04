# MenuLite

A tiny native macOS menu-bar app — system monitor + a few handy toggles.
SwiftUI + AppKit, real Liquid Glass, no dependencies.

## Features
- **System monitor** — CPU / memory / disk dials; click one for a live history graph, the top processes eating it, and a Network throughput tab.
- **Prevent sleep** — keeps your Mac awake (IOKit power assertion).
- **Dim external displays** — a brightness slider that overlays any external monitor.
- **Clean keyboard** — disables the keyboard so you can wipe it (needs Accessibility).

Right-click the menu-bar icon for **Launch at Login** and **Quit**.

## Build
```bash
./Scripts/build-app.sh && open dist/MenuLite.app
```
Requires **macOS 26 + Xcode 26** (uses the Liquid Glass APIs).

## Permissions
**Clean keyboard** needs Accessibility — approve MenuLite in *System Settings ▸
Privacy & Security ▸ Accessibility* on first use. Nothing else needs permission.

MIT © Ryan Truong. Clean-room — built by observing behavior, not decompiling any app.
