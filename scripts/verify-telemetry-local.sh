#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${DUMBTRANS_TELEMETRY_PORT:-17878}"
OUTPUT="${DUMBTRANS_TELEMETRY_OUTPUT:-$PROJECT_DIR/build/telemetry/events.jsonl}"
ENDPOINT="http://127.0.0.1:${PORT}/events"
PREF_DOMAIN="com.whimsycode.dumbtrans-pro"
PREF_KEY="shareAnonymousUsageData"
COLLECTOR_PID=""
HAD_PREF=false
OLD_PREF=""
INSTALLED_WITH_ENDPOINT=false
RESTORED_APP=false

cleanup() {
    if [[ -n "$COLLECTOR_PID" ]]; then
        kill "$COLLECTOR_PID" >/dev/null 2>&1 || true
        wait "$COLLECTOR_PID" >/dev/null 2>&1 || true
    fi

    if [[ "$HAD_PREF" == true ]]; then
        defaults write "$PREF_DOMAIN" "$PREF_KEY" -bool "$OLD_PREF" >/dev/null 2>&1 || true
    else
        defaults delete "$PREF_DOMAIN" "$PREF_KEY" >/dev/null 2>&1 || true
    fi

    if [[ "$INSTALLED_WITH_ENDPOINT" == true &&
          "$RESTORED_APP" != true &&
          "${DUMBTRANS_TELEMETRY_KEEP_ENDPOINT:-}" != "1" ]]; then
        echo "Restoring installed development app without a telemetry endpoint..." >&2
        bash "$PROJECT_DIR/scripts/bundle.sh" --install --launch >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $PORT is already in use. Set DUMBTRANS_TELEMETRY_PORT to another port." >&2
    exit 1
fi

if OLD_PREF="$(defaults read "$PREF_DOMAIN" "$PREF_KEY" 2>/dev/null)"; then
    HAD_PREF=true
else
    HAD_PREF=false
fi

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"

python3 "$PROJECT_DIR/scripts/telemetry_capture.py" --port "$PORT" --output "$OUTPUT" &
COLLECTOR_PID="$!"
sleep 0.5

defaults write "$PREF_DOMAIN" "$PREF_KEY" -bool true

echo "Building and launching app with local telemetry endpoint: $ENDPOINT"
DUMBTRANS_USAGE_TELEMETRY_URL="$ENDPOINT" bash "$PROJECT_DIR/scripts/bundle.sh" --install --launch
INSTALLED_WITH_ENDPOINT=true

echo "Waiting for first telemetry event..."
for _ in $(seq 1 30); do
    if [[ -s "$OUTPUT" ]]; then
        echo "Captured telemetry:"
        tail -n 5 "$OUTPUT"
        break
    fi
    sleep 0.5
done

if [[ ! -s "$OUTPUT" ]]; then
    echo "No telemetry captured. Check that the app launched and the anonymous usage data switch is enabled." >&2
    exit 1
fi

if [[ "${DUMBTRANS_TELEMETRY_KEEP_ENDPOINT:-}" != "1" ]]; then
    echo "Restoring installed development app without a telemetry endpoint..."
    bash "$PROJECT_DIR/scripts/bundle.sh" --install --launch
    RESTORED_APP=true
fi

echo "Telemetry local verification complete."
