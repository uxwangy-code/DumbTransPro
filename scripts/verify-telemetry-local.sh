#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${DUMBTRANS_TELEMETRY_PORT:-17878}"
OUTPUT="${DUMBTRANS_TELEMETRY_OUTPUT:-$PROJECT_DIR/build/telemetry/events.jsonl}"
ENDPOINT="http://127.0.0.1:${PORT}/events"
COLLECTOR_PID=""
cleanup() {
    if [[ -n "$COLLECTOR_PID" ]]; then
        kill "$COLLECTOR_PID" >/dev/null 2>&1 || true
        wait "$COLLECTOR_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $PORT is already in use; set DUMBTRANS_TELEMETRY_PORT." >&2
    exit 1
fi
mkdir -p "$(dirname "$OUTPUT")"
# Keep each verification capture separate from prior evidence.
if [[ -e "$OUTPUT" ]]; then OUTPUT="${OUTPUT%.jsonl}-$(date +%s).jsonl"; fi
python3 "$PROJECT_DIR/scripts/telemetry_capture.py" --port "$PORT" --output "$OUTPUT" &
COLLECTOR_PID="$!"
for _ in {1..30}; do
    if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then break; fi
    sleep 0.1
done
TEST_ARGS=()
SWIFT_BIN="${DUMBTRANS_SWIFT_BIN:-swift}"
if [[ "${DEVELOPER_DIR:-}" == "/Library/Developer/CommandLineTools" ]]; then
    SWIFT_BIN="/Library/Developer/CommandLineTools/usr/bin/swift"
    TEST_ARGS=(-Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks
               -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks
               -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
               -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib)
fi
cd "$PROJECT_DIR"
DTP_TEST_ENDPOINT="$ENDPOINT" "$SWIFT_BIN" test "${TEST_ARGS[@]}" --filter TelemetryLocalCaptureTests
python3 - "$OUTPUT" <<'PY'
import json, sys
with open(sys.argv[1]) as capture:
    events = [json.loads(line)['payload'] for line in capture]
assert len(events) == 3, f'expected 3 events, received {len(events)}'
assert {p['event']['name'] for p in events} == {'app_launched','translation_started','translation_succeeded'}
assert len({p['installationId'] for p in events}) == 1
assert len({p['eventId'] for p in events}) == 3
assert all(p['schemaVersion'] == 3 for p in events)
print(f'Verified 3 schema-v3 lifecycle events: {sys.argv[1]}')
PY
