# MenuLite

A tiny, clean macOS menu-bar app — a focused, clean-room take on a few
OneMenu-style utilities. Native SwiftUI + AppKit, no dependencies.

## Features
- **Live system stats** — CPU, memory, and disk usage right in the menu bar (`C12 M64`) and as bars in the dropdown.
- **Prevent sleep** — a toggle backed by an IOKit power assertion (no `caffeinate` process).
- **Dim external displays** — a slider that lays a translucent, click-through overlay over each external monitor (works on any display; no DDC needed).
- **Clean keyboard** — disables the keyboard so you can wipe it; a mouse-clickable overlay exits. Uses a `CGEventTap` (needs Accessibility permission).

## Build & run
```bash
./Scripts/build-app.sh
open dist/MenuLite.app
```
Requires Xcode 26 (macOS 26 SDK) and macOS 26+ — it uses the real Liquid Glass
(`.glassEffect`) APIs.

For development you can also just `swift run` (it'll show a Dock icon; the
packaged `.app` is a proper menu-bar agent via `LSUIElement`).

## Permissions
**Clean keyboard** needs Accessibility: the first time you use it, macOS prompts
you — approve **MenuLite** under *System Settings ▸ Privacy & Security ▸
Accessibility*. The other three features need no special permission.

> Note: the build is ad-hoc signed, so its identity changes when rebuilt; macOS
> may re-ask for Accessibility after a rebuild. Sign with a stable identity to
> avoid that.

## Layout
```
Sources/MenuLite/
  MenuLiteApp.swift     # @main, MenuBarExtra scene + app delegate
  AppState.swift        # observable state, poll timer, owns the managers
  StatsMonitor.swift    # CPU / memory / disk via mach + URL resource values
  SleepManager.swift    # IOKit power assertion
  DisplayDimmer.swift   # overlay windows on external screens
  KeyboardCleaner.swift # CGEventTap + exit overlay
  MenuContent.swift     # the dropdown UI
```

Clean-room: built from scratch by observing behavior, not decompiling any app.
MIT © Ryan Truong.
