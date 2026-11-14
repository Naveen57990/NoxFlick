#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Building FlikConnector in release mode..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/FlikConnector"
APP_NAME="Nox Flick.app"
APP_DIR="$SCRIPT_DIR/$APP_NAME"

echo "📦 Packaging $APP_NAME..."
rm -rf "$APP_DIR"
rm -rf "$SCRIPT_DIR/Flik Connector.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/FlikConnector"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "✍️ Ad-hoc code signing..."
codesign -s - --force --deep "$APP_DIR"

echo "✅ Build completed successfully: $APP_DIR"
