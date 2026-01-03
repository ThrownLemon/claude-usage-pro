#!/bin/bash

set -e

APP_NAME="ClaudeUsagePro"
BUNDLE_ID="com.sisyphus.ClaudeUsagePro"
VERSION="1.0.0"
BUILD_NUMBER=$(date +%Y%m%d%H%M)
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Cleaning old artifacts..."
rm -rf "$APP_BUNDLE"

echo "Building $APP_NAME in release mode..."
swift build -c release

EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Error: Build failed, executable not found at $EXECUTABLE_PATH" >&2
    exit 1
fi

echo "Creating .app bundle structure..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Copying executable and resources..."
cp "$EXECUTABLE_PATH" "$MACOS_DIR/"

ICON_PATH="Resources/$APP_NAME.icns"
if [ ! -f "$ICON_PATH" ]; then
    echo "Error: App icon not found at $ICON_PATH" >&2
    exit 1
fi
cp "$ICON_PATH" "$RESOURCES_DIR/"

echo "Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Build complete: $APP_BUNDLE"
echo "Note: For notifications to work, you may need to sign the app using 'codesign'."
