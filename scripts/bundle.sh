#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$PROJECT_DIR/build/DumbTransPro.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
INSTALL_APP=false
LAUNCH_APP=false
INSTALL_DIR="${DUMBTRANS_INSTALL_DIR:-/Applications}"
INSTALL_APP_NAME="${DUMBTRANS_INSTALL_APP_NAME:-瞎翻 Pro.app}"

usage() {
    cat <<EOF
Usage: bash scripts/bundle.sh [options]

Options:
  --install            Install the signed app into /Applications by default.
  --install-dir PATH   Install into PATH instead of /Applications.
  --launch             Open the installed app after --install.
  -h, --help           Show this help.

Environment:
  DUMBTRANS_INSTALL_DIR       Default install directory.
  DUMBTRANS_INSTALL_APP_NAME  Installed app bundle name.
  DUMBTRANS_SIGNING_IDENTITY  Code signing identity name.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            INSTALL_APP=true
            ;;
        --install-dir)
            shift
            if [[ $# -eq 0 ]]; then
                echo "Missing value for --install-dir" >&2
                exit 1
            fi
            INSTALL_DIR="$1"
            ;;
        --launch)
            LAUNCH_APP=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

register_with_launch_services() {
    local app_path="$1"
    local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    if [[ -x "$lsregister" ]]; then
        "$lsregister" -f "$app_path" >/dev/null 2>&1 || true
    fi
}

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
cp "$PROJECT_DIR/Resources/MenuBarIcon.png" \
   "$PROJECT_DIR/Resources/MenuBarIcon@2x.png" \
   "$PROJECT_DIR/Resources/MenuBarIcon@3x.png" \
   "$CONTENTS_DIR/Resources/"

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

if [[ "$INSTALL_APP" == true ]]; then
    echo "Installing..."
    mkdir -p "$INSTALL_DIR"

    if [[ ! -w "$INSTALL_DIR" ]]; then
        echo "  ⚠ install directory is not writable: $INSTALL_DIR" >&2
        echo "     Try: DUMBTRANS_INSTALL_DIR=\"\$HOME/Applications\" bash scripts/bundle.sh --install" >&2
        exit 1
    fi

    INSTALL_APP_DIR="$INSTALL_DIR/$INSTALL_APP_NAME"
    rm -rf "$INSTALL_APP_DIR"
    ditto "$APP_DIR" "$INSTALL_APP_DIR"
    register_with_launch_services "$INSTALL_APP_DIR"

    echo "Installed: $INSTALL_APP_DIR"
    echo "If Launchpad does not refresh immediately, run: killall Dock"

    if [[ "$LAUNCH_APP" == true ]]; then
        open "$INSTALL_APP_DIR"
    fi
fi

echo "Done: $APP_DIR"
