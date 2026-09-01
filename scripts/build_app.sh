#!/bin/bash
set -e

echo "🔨 Building SingleSense for macOS (Release)..."

# If Xcode-beta is present, set DEVELOPER_DIR to ensure complete SDK access
if [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
elif [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

swift build -c release

BIN_PATH=".build/release/SingleSense"
APP_BUNDLE="SingleSense.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Creating macOS App Bundle ($APP_BUNDLE)..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/SingleSense"
chmod +x "$MACOS_DIR/SingleSense"

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SingleSense</string>
    <key>CFBundleIdentifier</key>
    <string>com.singlesense.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SingleSense</string>
    <key>CFBundleDisplayName</key>
    <string>SingleSense</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 SingleSense. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>SingleSense requires Bluetooth access to communicate with and configure PS5 DualSense controllers.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>SingleSense requires Bluetooth access to communicate with and configure PS5 DualSense controllers.</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>SingleSense reads the system audio mix to drive the Music Sync lightbar mode. Audio is analysed in memory and never recorded or transmitted.</string>
</dict>
</plist>
EOF

# ScreenCaptureKit (Music Sync) is gated behind Screen Recording permission,
# and macOS will not grant that to an unsigned bundle. An ad-hoc signature is
# enough to be granted; note that it changes on every rebuild, so macOS will
# ask again after each build unless you sign with a real Developer ID.
echo "🔏 Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Successfully built and packaged SingleSense.app!"
echo "🚀 You can launch it using: open SingleSense.app"
