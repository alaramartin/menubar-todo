#!/bin/bash
# Builds "Menubar Todo.app" and (with --install) copies it to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/Menubar Todo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MenubarTodo "$APP/Contents/MacOS/MenubarTodo"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Menubar Todo</string>
    <key>CFBundleDisplayName</key><string>Menubar Todo</string>
    <key>CFBundleIdentifier</key><string>com.alaramartin.menubar-todo</string>
    <key>CFBundleExecutable</key><string>MenubarTodo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MenubarTodo || true
    rm -rf "/Applications/Menubar Todo.app"
    cp -R "$APP" /Applications/
    open "/Applications/Menubar Todo.app"
    echo "Installed to /Applications and launched"
fi
