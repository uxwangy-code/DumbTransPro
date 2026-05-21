#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
BUILD="${2:-}"
RELEASE_NOTES="${3:-}"

usage() {
    cat <<EOF
Usage: bash scripts/release-update.sh VERSION BUILD [release-notes.md]

Example:
  bash scripts/release-update.sh 1.2.0 120 RELEASE_NOTES.md

Environment:
  DUMBTRANS_SPARKLE_KEY_ACCOUNT       Keychain account for Sparkle EdDSA key.
  DUMBTRANS_SPARKLE_PUBLIC_ED_KEY     Sparkle public key override. Required in CI if Keychain is unavailable.
  DUMBTRANS_SPARKLE_FEED_URL          Appcast URL embedded in the app.
  DUMBTRANS_SPARKLE_DOWNLOAD_URL_PREFIX  URL prefix for update zip downloads.
  DUMBTRANS_SPARKLE_ED_KEY_FILE       Private EdDSA key file for generate_appcast.
  DUMBTRANS_APPCAST_PATH              Appcast file to write in the repo.
  DUMBTRANS_PRODUCT_LINK              Product link used by Sparkle.
  DUMBTRANS_RELEASE_WORK_DIR          Temporary release workspace.
EOF
}

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
    usage >&2
    exit 1
fi

if [[ "$VERSION" == v* ]]; then
    VERSION="${VERSION#v}"
fi

SPARKLE_ACCOUNT="${DUMBTRANS_SPARKLE_KEY_ACCOUNT:-com.whimsycode.dumbtrans-pro}"
FEED_URL="${DUMBTRANS_SPARKLE_FEED_URL:-https://uxwangy-code.github.io/DumbTransPro/appcast.xml}"
DOWNLOAD_URL_PREFIX="${DUMBTRANS_SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/uxwangy-code/DumbTransPro/releases/download/v${VERSION}/}"
PRODUCT_LINK="${DUMBTRANS_PRODUCT_LINK:-https://github.com/uxwangy-code/DumbTransPro}"
APPCAST_PATH="${DUMBTRANS_APPCAST_PATH:-$PROJECT_DIR/docs/appcast.xml}"
WORK_DIR="${DUMBTRANS_RELEASE_WORK_DIR:-$PROJECT_DIR/build/sparkle-release/v${VERSION}}"
ARCHIVE_NAME="DumbTransPro-${VERSION}.zip"
ARCHIVE_PATH="$WORK_DIR/$ARCHIVE_NAME"
GENERATE_KEYS="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
GENERATE_APPCAST="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

if [[ ! -x "$GENERATE_KEYS" || ! -x "$GENERATE_APPCAST" ]]; then
    echo "Resolving Sparkle tools..."
    (cd "$PROJECT_DIR" && swift package resolve)
fi

if [[ ! -x "$GENERATE_KEYS" || ! -x "$GENERATE_APPCAST" ]]; then
    echo "Sparkle tools not found. Try: swift package resolve" >&2
    exit 1
fi

PUBLIC_KEY="${DUMBTRANS_SPARKLE_PUBLIC_ED_KEY:-}"
if [[ -z "$PUBLIC_KEY" ]]; then
    if ! PUBLIC_KEY="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null)"; then
        echo "Sparkle signing key not found." >&2
        echo "Run first: bash scripts/setup-sparkle.sh" >&2
        exit 1
    fi
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "Building release app v${VERSION} (${BUILD})..."
DUMBTRANS_VERSION="$VERSION" \
DUMBTRANS_BUILD="$BUILD" \
DUMBTRANS_SPARKLE_FEED_URL="$FEED_URL" \
DUMBTRANS_SPARKLE_PUBLIC_ED_KEY="$PUBLIC_KEY" \
    bash "$PROJECT_DIR/scripts/bundle.sh"

echo "Creating update archive: $ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_DIR/build/DumbTransPro.app" "$ARCHIVE_PATH"

if [[ -n "$RELEASE_NOTES" ]]; then
    if [[ ! -f "$RELEASE_NOTES" ]]; then
        echo "Release notes file not found: $RELEASE_NOTES" >&2
        exit 1
    fi
    cp "$RELEASE_NOTES" "$WORK_DIR/DumbTransPro-${VERSION}.md"
else
    cat > "$WORK_DIR/DumbTransPro-${VERSION}.md" <<EOF
# 瞎翻 Pro v${VERSION}

- 例行更新。
EOF
fi

if [[ -f "$APPCAST_PATH" ]]; then
    cp "$APPCAST_PATH" "$WORK_DIR/appcast.xml"
fi

appcast_args=(
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
    --link "$PRODUCT_LINK"
    --embed-release-notes
    --maximum-versions 10
)

if [[ -n "${DUMBTRANS_SPARKLE_ED_KEY_FILE:-}" ]]; then
    appcast_args+=(--ed-key-file "$DUMBTRANS_SPARKLE_ED_KEY_FILE")
else
    appcast_args+=(--account "$SPARKLE_ACCOUNT")
fi

echo "Generating Sparkle appcast..."
"$GENERATE_APPCAST" "${appcast_args[@]}" "$WORK_DIR"

mkdir -p "$(dirname "$APPCAST_PATH")"
cp "$WORK_DIR/appcast.xml" "$APPCAST_PATH"

RELATIVE_APPCAST_PATH="$APPCAST_PATH"
if [[ "$RELATIVE_APPCAST_PATH" == "$PROJECT_DIR/"* ]]; then
    RELATIVE_APPCAST_PATH="${RELATIVE_APPCAST_PATH#"$PROJECT_DIR"/}"
fi

echo ""
echo "Release artifacts ready:"
echo "  Update archive: $ARCHIVE_PATH"
echo "  Appcast:        $APPCAST_PATH"
echo ""
echo "Next:"
echo "  1. Create GitHub release tag v${VERSION}."
echo "  2. Upload $ARCHIVE_NAME to that release."
echo "  3. Commit and publish $RELATIVE_APPCAST_PATH."
