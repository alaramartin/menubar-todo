#!/bin/bash
# Builds "Menubar Todo.app" (universal: Apple silicon + Intel).
#   --install   also copy it to /Applications and launch it
#   --zip       also make build/MenubarTodo.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

# Version = the newest release tag (v1.2.1 → 1.2.1), unless VERSION is set. scripts/release.sh sets it for a new release.
git fetch --tags -q 2>/dev/null || true
LATEST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
VERSION="${VERSION:-${LATEST_TAG#v}}"
VERSION="${VERSION:-0.0.0}"
swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/MenubarTodo"
APP="build/Menubar Todo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp "$BIN" "$APP/Contents/MacOS/MenubarTodo"
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
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
# Sign with a stable identity when there is one, so macOS keeps the Accessibility permission across
# rebuilds (an ad-hoc signature changes every build, which silently revokes it). Override with SIGN_ID.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"

if [[ " $* " == *" --zip "* ]]; then
    rm -f build/MenubarTodo.zip
    ditto -c -k --keepParent "$APP" build/MenubarTodo.zip
    echo "Zipped build/MenubarTodo.zip"
fi

if [[ " $* " == *" --install "* ]]; then
    pkill -x MenubarTodo || true
    rm -rf "/Applications/Menubar Todo.app"
    mv "$APP" /Applications/ # move, not copy, so Spotlight and Settings only see one app
    open "/Applications/Menubar Todo.app"
    echo "Installed to /Applications and launched"
fi
