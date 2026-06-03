#!/usr/bin/env bash
# Build MenuLite and assemble a runnable .app bundle (menu-bar agent).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="MenuLite"
BUNDLE_ID="com.heyodog0.menulite"
VERSION="0.1.0"
APP="dist/$APP_NAME.app"

echo "▶ Building release binary…"
swift build -c release

echo "▶ Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS can attach Accessibility permission to the bundle.
echo "▶ Signing (ad-hoc)…"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  codesign --force --sign - "$APP"

echo "✓ Built $APP"
echo "  Run:  open \"$APP\""
echo "  Keyboard cleaning needs Accessibility: System Settings ▸ Privacy & Security ▸ Accessibility."
