#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

VERSION="1.0.0"
if [ -f "$DIR/VERSION" ]; then
    VERSION=$(cat "$DIR/VERSION" | tr -d '[:space:]')
fi

# Stamp version into Resources/Info.plist
plutil -replace CFBundleShortVersionString -string "$VERSION" "$DIR/Resources/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$DIR/Resources/Info.plist"

echo "=========================================="
echo "    Building Roblox Watcher Suite v$VERSION"
echo "=========================================="

# 1. Build CLI Tool (Universal Binary: arm64 + x86_64)
CLI_NAME="roblox-watcher-v${VERSION}"
echo "==> [1/3] Compiling CLI binary ($CLI_NAME, Universal)..."
swiftc -O -target arm64-apple-macos14.0 \
    -framework Vision \
    -framework AppKit \
    -framework CoreGraphics \
    Sources/main.swift \
    -o "$DIR/${CLI_NAME}_arm64"

swiftc -O -target x86_64-apple-macos14.0 \
    -framework Vision \
    -framework AppKit \
    -framework CoreGraphics \
    Sources/main.swift \
    -o "$DIR/${CLI_NAME}_x86_64"

lipo -create -output "$DIR/$CLI_NAME" "$DIR/${CLI_NAME}_arm64" "$DIR/${CLI_NAME}_x86_64"
rm -f "$DIR/${CLI_NAME}_arm64" "$DIR/${CLI_NAME}_x86_64"
chmod +x "$DIR/$CLI_NAME"
codesign --force --sign - "$DIR/$CLI_NAME" 2>/dev/null || true
ln -sf "$DIR/$CLI_NAME" "$DIR/roblox-watcher"

# 2. Build Native macOS App Bundle (Universal Binary: arm64 + x86_64)
echo "==> [2/3] Assembling Roblox Watcher.app (v$VERSION, Universal)..."
APP_NAME="Roblox Watcher.app"
CONTENTS_DIR="$DIR/$APP_NAME/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$DIR/$APP_NAME"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy Plist & Assets
cp "$DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$CONTENTS_DIR/Info.plist"

cp "$DIR/VERSION" "$RESOURCES_DIR/VERSION"
cp "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$DIR/Resources/app_icon.png" "$RESOURCES_DIR/app_icon.png"
cp "$DIR/Resources/menubar_active.png" "$RESOURCES_DIR/menubar_active.png"
cp "$DIR/Resources/menubar_inactive.png" "$RESOURCES_DIR/menubar_inactive.png"
cp "$DIR/Resources/index.html" "$RESOURCES_DIR/index.html"

# Compile NativeApp executable (Universal: arm64 + x86_64)
swiftc -O -target arm64-apple-macos14.0 \
    -framework AppKit \
    -framework WebKit \
    -framework Vision \
    -framework CoreGraphics \
    -framework ImageIO \
    Sources/NativeApp.swift \
    -o "$MACOS_DIR/RobloxWatcher_arm64"

swiftc -O -target x86_64-apple-macos14.0 \
    -framework AppKit \
    -framework WebKit \
    -framework Vision \
    -framework CoreGraphics \
    -framework ImageIO \
    Sources/NativeApp.swift \
    -o "$MACOS_DIR/RobloxWatcher_x86_64"

lipo -create -output "$MACOS_DIR/RobloxWatcher" "$MACOS_DIR/RobloxWatcher_arm64" "$MACOS_DIR/RobloxWatcher_x86_64"
rm -f "$MACOS_DIR/RobloxWatcher_arm64" "$MACOS_DIR/RobloxWatcher_x86_64"
chmod +x "$MACOS_DIR/RobloxWatcher"

# Ad-hoc code sign bundle for Gatekeeper compatibility
echo "==> Signing app bundle..."
codesign --force --deep --sign - "$DIR/$APP_NAME"

# 3. Create DMG Installer
DMG_NAME="Roblox-Watcher-v${VERSION}.dmg"
echo "==> [3/3] Packaging disk image ($DMG_NAME)..."
STAGING_DIR="$DIR/.build/dmg_staging"

rm -rf "$STAGING_DIR" "$DIR/$DMG_NAME" "$DIR/Roblox Watcher.dmg"
mkdir -p "$STAGING_DIR"

# Copy App and link Applications folder
cp -R "$DIR/$APP_NAME" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create compressed read-only DMG with drag-and-drop support
hdiutil create \
    -volname "Roblox Watcher" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DIR/$DMG_NAME" > /dev/null

ln -sf "$DIR/$DMG_NAME" "$DIR/Roblox Watcher.dmg"
rm -rf "$DIR/.build"

echo "=========================================="
echo " Build Success!"
echo " - Version:    $VERSION (Universal: arm64 + x86_64)"
echo " - CLI Tool:   $DIR/$CLI_NAME (linked as roblox-watcher)"
echo " - macOS App:  $DIR/$APP_NAME"
echo " - DMG Image:  $DIR/$DMG_NAME"
echo "=========================================="
