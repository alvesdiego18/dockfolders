#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="DockFoldersLocator.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DockFoldersLocator</string>
    <key>CFBundleDisplayName</key><string>DockFolders Locator</string>
    <key>CFBundleIdentifier</key><string>local.dockfolders.locator</string>
    <key>CFBundleExecutable</key><string>DockFoldersLocator</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
swiftc -O DockTileLocator.swift main.swift -o "$APP/Contents/MacOS/DockFoldersLocator"
codesign --force --sign - "$APP" 2>/dev/null || true
echo "OK: $(pwd)/$APP"
