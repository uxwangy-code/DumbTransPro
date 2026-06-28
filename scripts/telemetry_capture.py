#!/usr/bin/env python3
import argparse
import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict


TOP_LEVEL_FIELDS = {"schemaVersion", "sentAt", "context", "event"}
CONTEXT_FIELDS = {"appVersion", "macOSVersion"}
EVENT_FIELDS = {"name", "action", "route", "provider", "direction", "style", "licenseTier", "errorKind"}
FORBIDDEN_FIELDS = {
    "apiKey",
    "licenseKey",
    "clipboard",
    "clipboardText",
    "sourceText",
    "translatedText",
    "inputText",
    "outputText",
    "customEndpoint",
    "endpoint",
    "model",
    "deviceId",
    "email",
    "userName",
    "fullName",
}
EVENT_NAMES = {"app_launched", "translation_succeeded", "translation_failed", "translation_blocked"}
ACTIONS = {"rewrite", "lookup"}
ROUTES = {"ai", "offline"}
PROVIDERS = {"openai", "zhipu", "deepseek", "kimi", "minimax", "qwen", "doubao", "custom"}
DIRECTIONS = {"chinese_to_english", "foreign_to_chinese"}
STYLES = {"plain", "natural", "elegant"}
LICENSE_TIERS = {"free", "pro"}
ERROR_KINDS = {
    "no_selection",
    "needs_setup",
    "provider_locked",
    "daily_limit_reached",
    "offline_language_missing",
    "timeout",
    "content_blocked",
    "api_error",
    "network",
    "invalid_response",
    "unknown",
}


def validate_payload(payload: Dict[str, Any]) -> None:
    if not isinstance(payload, dict):
        raise ValueError("payload must be an object")

    reject_forbidden_fields(payload)

    unknown = set(payload) - TOP_LEVEL_FIELDS
    if unknown:
        raise ValueError(f"unknown top-level field: {sorted(unknown)[0]}")

    if payload.get("schemaVersion") != 1:
        raise ValueError("schemaVersion must be 1")
    if not isinstance(payload.get("sentAt"), str) or not payload["sentAt"]:
        raise ValueError("sentAt must be a non-empty string")

    context = payload.get("context")
    if not isinstance(context, dict):
        raise ValueError("context must be an object")
    unknown_context = set(context) - CONTEXT_FIELDS
    if unknown_context:
        raise ValueError(f"unknown context field: {sorted(unknown_context)[0]}")
    require_string(context, "appVersion", "context.appVersion")
    require_string(context, "macOSVersion", "context.macOSVersion")

    event = payload.get("event")
    if not isinstance(event, dict):
        raise ValueError("event must be an object")
    unknown_event = set(event) - EVENT_FIELDS
    if unknown_event:
        raise ValueError(f"unknown event field: {sorted(unknown_event)[0]}")

    require_enum(event, "name", EVENT_NAMES, "event.name")
    optional_enum(event, "action", ACTIONS, "event.action")
    optional_enum(event, "route", ROUTES, "event.route")
    optional_enum(event, "provider", PROVIDERS, "event.provider")
    optional_enum(event, "direction", DIRECTIONS, "event.direction")
    optional_enum(event, "style", STYLES, "event.style")
    optional_enum(event, "licenseTier", LICENSE_TIERS, "event.licenseTier")
    optional_enum(event, "errorKind", ERROR_KINDS, "event.errorKind")


def reject_forbidden_fields(value: Any) -> None:
    if isinstance(value, dict):
        for key, nested in value.items():
            if key in FORBIDDEN_FIELDS:
                raise ValueError(f"forbidden field: {key}")
            reject_forbidden_fields(nested)
    elif isinstance(value, list):
        for item in value:
            reject_forbidden_fields(item)


def require_string(data: Dict[str, Any], key: str, label: str) -> None:
    if not isinstance(data.get(key), str) or not data[key]:
        raise ValueError(f"{label} must be a non-empty string")


def require_enum(data: Dict[str, Any], key: str, allowed: set, label: str) -> None:
    value = data.get(key)
    if value not in allowed:
        raise ValueError(f"invalid {label}: {value}")


def optional_enum(data: Dict[str, Any], key: str, allowed: set, label: str) -> None:
    value = data.get(key)
    if value is None:
        return
    if value not in allowed:
        raise ValueError(f"invalid {label}: {value}")


def make_handler(output_path: Path):
    class TelemetryCaptureHandler(BaseHTTPRequestHandler):
        server_version = "DumbTransTelemetryCapture/1.0"

        def do_POST(self):
            if self.path != "/events":
                self.send_error(404, "not found")
                return

            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > 32_768:
                    raise ValueError("invalid body length")
                body = self.rfile.read(length)
                payload = json.loads(body.decode("utf-8"))
                validate_payload(payload)
                output_path.parent.mkdir(parents=True, exist_ok=True)
                record = {
                    "receivedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                    "payload": payload,
                }
                with output_path.open("a", encoding="utf-8") as handle:
                    handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
                self.send_response(202)
                self.end_headers()
                self.wfile.write(b"accepted\n")
            except Exception as error:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(f"rejected: {error}\n".encode("utf-8"))

        def log_message(self, fmt, *args):
            print(fmt % args)

    return TelemetryCaptureHandler


def main() -> None:
    parser = argparse.ArgumentParser(description="Capture DumbTransPro telemetry events locally.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=17878, type=int)
    parser.add_argument("--output", default="build/telemetry/events.jsonl")
    args = parser.parse_args()

    output_path = Path(args.output)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(output_path))
    print(f"Listening on http://{args.host}:{args.port}/events")
    print(f"Writing accepted events to {output_path}")
    server.serve_forever()


if __name__ == "__main__":
    main()
