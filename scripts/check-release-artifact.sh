#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${DUMBTRANS_RELEASE_APP_PATH:-$PROJECT_DIR/build/DumbTransPro.app}"
PLIST="$APP_PATH/Contents/Info.plist"
PLISTBUDDY="/usr/libexec/PlistBuddy"

EXPECTED_USAGE_TELEMETRY_URL="${DUMBTRANS_EXPECTED_USAGE_TELEMETRY_URL:-https://dumbtranspro-telemetry.whimsycode.workers.dev/events}"
EXPECTED_LICENSE_PURCHASE_URL="${DUMBTRANS_EXPECTED_LICENSE_PURCHASE_URL:-https://uxwangy-code.github.io/DumbTransPro/#pricing}"
EXPECTED_LICENSE_VERIFY_URL="${DUMBTRANS_EXPECTED_LICENSE_VERIFY_URL:-https://license.whimsycode.com/api/licenses/verify}"
EXPECTED_VERSION="${DUMBTRANS_EXPECTED_VERSION:-}"
EXPECTED_BUILD="${DUMBTRANS_EXPECTED_BUILD:-}"

failures=0

read_plist_value() {
    local key="$1"
    "$PLISTBUDDY" -c "Print :${key}" "$PLIST" 2>/dev/null || true
}

record_failure() {
    echo "Release artifact check failed: $1" >&2
    failures=$((failures + 1))
}

expect_equals() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(read_plist_value "$key")"

    if [[ -z "$actual" ]]; then
        record_failure "${key} is missing or empty"
        return
    fi
    if [[ "$actual" != "$expected" ]]; then
        record_failure "${key} expected '${expected}', got '${actual}'"
    fi
}

if [[ ! -f "$PLIST" ]]; then
    echo "Release artifact check failed: Info.plist not found at $PLIST" >&2
    exit 1
fi

if [[ -n "$EXPECTED_VERSION" ]]; then
    expect_equals "CFBundleShortVersionString" "$EXPECTED_VERSION"
fi
if [[ -n "$EXPECTED_BUILD" ]]; then
    expect_equals "CFBundleVersion" "$EXPECTED_BUILD"
fi

expect_equals "DTPUsageTelemetryURL" "$EXPECTED_USAGE_TELEMETRY_URL"
expect_equals "DTPLicensePurchaseURL" "$EXPECTED_LICENSE_PURCHASE_URL"
expect_equals "DTPLicenseVerifyURL" "$EXPECTED_LICENSE_VERIFY_URL"

if [[ "$failures" -gt 0 ]]; then
    exit 1
fi

echo "Release artifact configuration OK."
