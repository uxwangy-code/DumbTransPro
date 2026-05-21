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
  DUMBTRANS_SIGNING_KEYCHAIN_PATH  Dedicated signing keychain path.
  DUMBTRANS_SIGNING_KEYCHAIN_PASS  Dedicated signing keychain password.
  DUMBTRANS_VERSION           CFBundleShortVersionString override.
  DUMBTRANS_BUILD             CFBundleVersion override.
  DUMBTRANS_SPARKLE_FEED_URL  Sparkle appcast URL override.
  DUMBTRANS_SPARKLE_KEY_ACCOUNT  Keychain account for Sparkle EdDSA key.
  DUMBTRANS_SPARKLE_PUBLIC_ED_KEY  Sparkle EdDSA public key for update verification.
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

quit_running_app() {
    local bundle_id="com.whimsycode.dumbtrans-pro"
    local executable_name="DumbTransPro"

    if ! pgrep -x "$executable_name" >/dev/null 2>&1; then
        return 0
    fi

    echo "Stopping running ${executable_name} before relaunch..."
    osascript -e "tell application id \"${bundle_id}\" to quit" >/dev/null 2>&1 || true

    for _ in {1..15}; do
        if ! pgrep -x "$executable_name" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done

    echo "  → graceful quit timed out; sending terminate signal."
    pkill -x "$executable_name" >/dev/null 2>&1 || true
}

set_plist_string() {
    local key="$1"
    local value="$2"
    local plist="$CONTENTS_DIR/Info.plist"
    local plistbuddy="/usr/libexec/PlistBuddy"

    if [[ -z "$value" ]]; then
        return 0
    fi

    if "$plistbuddy" -c "Print :${key}" "$plist" >/dev/null 2>&1; then
        "$plistbuddy" -c "Set :${key} ${value}" "$plist"
    else
        "$plistbuddy" -c "Add :${key} string ${value}" "$plist"
    fi
}

configure_info_plist() {
    set_plist_string "CFBundleShortVersionString" "${DUMBTRANS_VERSION:-}"
    set_plist_string "CFBundleVersion" "${DUMBTRANS_BUILD:-}"
    set_plist_string "SUFeedURL" "${DUMBTRANS_SPARKLE_FEED_URL:-}"

    local public_key="${DUMBTRANS_SPARKLE_PUBLIC_ED_KEY:-}"
    local sparkle_account="${DUMBTRANS_SPARKLE_KEY_ACCOUNT:-com.whimsycode.dumbtrans-pro}"
    local generate_keys="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys"

    if [[ -z "$public_key" && -x "$generate_keys" ]]; then
        public_key="$("$generate_keys" --account "$sparkle_account" -p 2>/dev/null || true)"
    fi

    if [[ -n "$public_key" ]]; then
        set_plist_string "SUPublicEDKey" "$public_key"
    else
        echo "  ⚠ Sparkle public key is not configured; update checks will be disabled in this build."
        echo "     Fix: run ./scripts/setup-sparkle.sh once, or set DUMBTRANS_SPARKLE_PUBLIC_ED_KEY."
    fi
}

copy_sparkle_framework() {
    local framework_source
    framework_source="$(find "$PROJECT_DIR/.build/artifacts" -path "*/macos-arm64_x86_64/Sparkle.framework" -type d 2>/dev/null | head -n 1)"

    if [[ -z "$framework_source" ]]; then
        echo "  ✗ Sparkle.framework not found. Try: swift package resolve" >&2
        exit 1
    fi

    mkdir -p "$CONTENTS_DIR/Frameworks"
    rm -rf "$CONTENTS_DIR/Frameworks/Sparkle.framework"
    ditto "$framework_source" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
}

add_bundle_rpath() {
    local executable="$MACOS_DIR/DumbTransPro"
    local rpath="@executable_path/../Frameworks"

    if otool -l "$executable" | grep -q "$rpath"; then
        return 0
    fi

    install_name_tool -add_rpath "$rpath" "$executable"
}

echo "Building..."
cd "$PROJECT_DIR"
swift build -c release

echo "Packaging..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BUILD_DIR/DumbTransPro" "$MACOS_DIR/"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/"
configure_info_plist

mkdir -p "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/"
cp "$PROJECT_DIR/Resources/MenuBarIcon.png" \
   "$PROJECT_DIR/Resources/MenuBarIcon@2x.png" \
   "$PROJECT_DIR/Resources/MenuBarIcon@3x.png" \
   "$CONTENTS_DIR/Resources/"
copy_sparkle_framework
add_bundle_rpath

echo "Signing..."
SIGNING_IDENTITY="${DUMBTRANS_SIGNING_IDENTITY:-DumbTransPro Dev}"
SIGNING_KEYCHAIN_PATH="${DUMBTRANS_SIGNING_KEYCHAIN_PATH:-${HOME}/Library/Keychains/dumbtrans-signing.keychain-db}"
SIGNING_KEYCHAIN_PASS="${DUMBTRANS_SIGNING_KEYCHAIN_PASS:-dumbtrans-local-dev}"

sign_adhoc() {
    echo "  ⚠ falling back to adhoc signing."
    echo "     TCC grants (Accessibility) will NOT persist across rebuilds."
    echo "     Fix: run ./scripts/setup-signing.sh once, or recreate the signing keychain if it is locked with a different password."
    codesign --force --sign - "$APP_DIR"
}

sign_with_identity() {
    local codesign_args=(--force --deep --sign "${SIGNING_IDENTITY}")

    if [[ -f "${SIGNING_KEYCHAIN_PATH}" ]] &&
       security find-identity -p codesigning "${SIGNING_KEYCHAIN_PATH}" 2>/dev/null | grep -q "\"${SIGNING_IDENTITY}\""; then
        echo "  → using identity: ${SIGNING_IDENTITY}"
        echo "  → keychain: ${SIGNING_KEYCHAIN_PATH}"

        if ! security unlock-keychain -p "${SIGNING_KEYCHAIN_PASS}" "${SIGNING_KEYCHAIN_PATH}" >/dev/null 2>&1; then
            echo "  ⚠ could not unlock signing keychain non-interactively."
            return 1
        fi

        codesign_args+=(--keychain "${SIGNING_KEYCHAIN_PATH}")
    elif security find-identity -p codesigning 2>/dev/null | grep -q "\"${SIGNING_IDENTITY}\""; then
        echo "  → using identity: ${SIGNING_IDENTITY}"
    else
        echo "  ⚠ identity '${SIGNING_IDENTITY}' not found."
        return 1
    fi

    if ! codesign "${codesign_args[@]}" "$APP_DIR"; then
        echo "  ⚠ signing with '${SIGNING_IDENTITY}' failed."
        return 1
    fi
}

# Drop -v so we accept self-signed (untrusted but present) identities.
# codesign signs fine with them; TCC matches on the cert's designated
# requirement, not trust chain.
if ! sign_with_identity; then
    sign_adhoc
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
    if [[ "$LAUNCH_APP" == true ]]; then
        quit_running_app
    fi

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
