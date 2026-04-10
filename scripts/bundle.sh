#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$PROJECT_DIR/build/DumbTransPro.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

echo "Building..."
cd "$PROJECT_DIR"
swift build -c release

echo "Packaging..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BUILD_DIR/DumbTransPro" "$MACOS_DIR/"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/"

echo "Signing..."
codesign --force --sign - "$APP_DIR"

echo "Done: $APP_DIR"
