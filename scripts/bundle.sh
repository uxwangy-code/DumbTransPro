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

mkdir -p "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/"

echo "Signing..."
SIGNING_IDENTITY="${DUMBTRANS_SIGNING_IDENTITY:-DumbTransPro Dev}"
# Drop -v so we accept self-signed (untrusted but present) identities.
# codesign signs fine with them; TCC matches on the cert's designated
# requirement, not trust chain.
if security find-identity -p codesigning | grep -q "\"${SIGNING_IDENTITY}\""; then
    echo "  → using identity: ${SIGNING_IDENTITY}"
    codesign --force --deep --sign "${SIGNING_IDENTITY}" "$APP_DIR"
else
    echo "  ⚠ identity '${SIGNING_IDENTITY}' not found — falling back to adhoc."
    echo "     TCC grants (Accessibility) will NOT persist across rebuilds."
    echo "     Fix: run ./scripts/setup-signing.sh once to create the identity."
    codesign --force --sign - "$APP_DIR"
fi

echo "Done: $APP_DIR"
