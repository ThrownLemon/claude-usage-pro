#!/bin/bash

set -e

APP_NAME="ClaudeUsagePro"
BUNDLE_ID="com.sisyphus.ClaudeUsagePro"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building $APP_NAME in release mode..."
swift build -c release

echo "Cleaning up old build artifacts..."
rm -rf "$APP_BUNDLE"

echo "Creating .app bundle structure..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Copying executable..."
EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Error: Build succeeded but executable not found at $EXECUTABLE_PATH" >&2
    exit 1
fi
cp "$EXECUTABLE_PATH" "$MACOS_DIR/"

echo "Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
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
