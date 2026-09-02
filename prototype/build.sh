#!/bin/bash
# Compila o protótipo num bundle .app, para que ele se comporte como um app de
# verdade (ícone no Dock, ativação) — mesmas condições do app final.
set -euo pipefail

cd "$(dirname "$0")"
APP="DockFoldersProto.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DockFoldersProto</string>
    <key>CFBundleDisplayName</key><string>DockFolders Proto</string>
    <key>CFBundleIdentifier</key><string>local.dockfolders.proto</string>
    <key>CFBundleExecutable</key><string>DockFoldersProto</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

swiftc -O main.swift -o "$APP/Contents/MacOS/DockFoldersProto"
codesign --force --sign - "$APP" 2>/dev/null || true

echo "OK: $(pwd)/$APP"
