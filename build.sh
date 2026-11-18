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

# 0. Run Automated Unit Test Suite
echo "==> [0/3] Running automated unit test suite..."
"$DIR/test.sh"

# 1. Build CLI Tool (Universal Binary: arm64 + x86_64)
CLI_NAME="roblox-watcher-v${VERSION}"

# Determine Code Signing Identity:
# - In CI/GHA or when --release is passed: Use pure ad-hoc (-) so foreign Macs do not fail cert validation.
# - In local development: Use RobloxWatcherDev to preserve local TCC Accessibility & Screen Recording permissions.
SIGN_IDENTITY="-"
if [ "$1" = "--release" ] || [ "$1" = "--adhoc" ] || [ "$GITHUB_ACTIONS" = "true" ] || [ "$CI" = "true" ]; then
    echo "==> [Release Build] Signing with ad-hoc (-) for public distribution..."
elif security find-identity -p codesigning 2>/dev/null | grep -q "RobloxWatcherDev"; then
    SIGN_IDENTITY="RobloxWatcherDev"
    echo "==> [Local Dev Build] Using persistent identity to preserve macOS permissions: $SIGN_IDENTITY"
fi

echo "==> [1/3] Compiling CLI binary ($CLI_NAME, Universal)..."
swiftc -O -target arm64-apple-macos14.0 \
    -framework Vision \
    -framework AppKit \
    -framework CoreGraphics \
    Sources/Core/*.swift \
    Sources/CLI/*.swift \
    -o "$DIR/${CLI_NAME}_arm64"

swiftc -O -target x86_64-apple-macos14.0 \
    -framework Vision \
    -framework AppKit \
    -framework CoreGraphics \
    Sources/Core/*.swift \
    Sources/CLI/*.swift \
    -o "$DIR/${CLI_NAME}_x86_64"

lipo -create -output "$DIR/$CLI_NAME" "$DIR/${CLI_NAME}_arm64" "$DIR/${CLI_NAME}_x86_64"
rm -f "$DIR/${CLI_NAME}_arm64" "$DIR/${CLI_NAME}_x86_64"
chmod +x "$DIR/$CLI_NAME"
codesign --force --sign "$SIGN_IDENTITY" "$DIR/$CLI_NAME" 2>/dev/null || true
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
    Sources/Core/*.swift \
    Sources/App/*.swift \
    -o "$MACOS_DIR/RobloxWatcher_arm64"

swiftc -O -target x86_64-apple-macos14.0 \
    -framework AppKit \
    -framework WebKit \
    -framework Vision \
    -framework CoreGraphics \
    -framework ImageIO \
    Sources/Core/*.swift \
    Sources/App/*.swift \
    -o "$MACOS_DIR/RobloxWatcher_x86_64"

lipo -create -output "$MACOS_DIR/RobloxWatcher" "$MACOS_DIR/RobloxWatcher_arm64" "$MACOS_DIR/RobloxWatcher_x86_64"
rm -f "$MACOS_DIR/RobloxWatcher_arm64" "$MACOS_DIR/RobloxWatcher_x86_64"
chmod +x "$MACOS_DIR/RobloxWatcher"

# Code sign bundle (uses persistent identity if found, falls back to ad-hoc)
echo "==> Signing app bundle with identity: $SIGN_IDENTITY..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$DIR/$APP_NAME"

# 3. Create Distribution ZIP Archive (Avoids Chrome Safe Browsing DMG blocks)
ZIP_NAME="Roblox-Watcher-v${VERSION}.zip"
echo "==> [3/3] Packaging native ZIP archive ($ZIP_NAME)..."
rm -f "$DIR/$ZIP_NAME" "$DIR/Roblox Watcher.zip"
ditto -c -k --sequesterRsrc --keepParent "$DIR/$APP_NAME" "$DIR/$ZIP_NAME"
ln -sf "$DIR/$ZIP_NAME" "$DIR/Roblox Watcher.zip"

echo "=========================================="
echo " Build Success!"
echo " - Version:    $VERSION (Universal: arm64 + x86_64)"
echo " - CLI Tool:   $DIR/$CLI_NAME (linked as roblox-watcher)"
echo " - macOS App:  $DIR/$APP_NAME"
echo " - ZIP Archive: $DIR/$ZIP_NAME"
echo "=========================================="
