#!/bin/bash
# Build local do DockFolders. DEBUG=1 libera captura de tela para verificação visual.
set -euo pipefail
cd "$(dirname "$0")"

APP="DockFolders.app"
DEBUG_FLAG=""
[ "${DEBUG:-0}" = "1" ] && DEBUG_FLAG="-D DEBUG"

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DockFolders</string>
    <key>CFBundleDisplayName</key><string>DockFolders</string>
    <key>CFBundleIdentifier</key><string>local.dockfolders.app</string>
    <key>CFBundleExecutable</key><string>DockFolders</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# shellcheck disable=SC2086
swiftc -O $DEBUG_FLAG Sources/*.swift -o "$APP/Contents/MacOS/DockFolders"
codesign --force --sign - "$APP" 2>/dev/null || true
echo "OK: $(pwd)/$APP  (debug=${DEBUG:-0})"
