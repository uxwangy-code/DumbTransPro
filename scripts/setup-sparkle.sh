#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_ACCOUNT="${DUMBTRANS_SPARKLE_KEY_ACCOUNT:-com.whimsycode.dumbtrans-pro}"
GENERATE_KEYS="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys"

if [[ ! -x "$GENERATE_KEYS" ]]; then
    echo "Resolving Sparkle tools..."
    (cd "$PROJECT_DIR" && swift package resolve)
fi

if [[ ! -x "$GENERATE_KEYS" ]]; then
    echo "Sparkle generate_keys tool not found. Try: swift package resolve" >&2
    exit 1
fi

echo "Using Sparkle key account: $SPARKLE_ACCOUNT"
echo ""
"$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT"

PUBLIC_KEY="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p)"
echo "For release builds, bundle.sh can inject this public key automatically via:"
echo "  DUMBTRANS_SPARKLE_PUBLIC_ED_KEY=\"$PUBLIC_KEY\""
