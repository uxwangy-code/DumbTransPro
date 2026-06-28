import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

from telemetry_capture import validate_payload


VALID_PAYLOAD = {
    "schemaVersion": 1,
    "sentAt": "2026-06-28T10:00:00Z",
    "context": {
        "appVersion": "1.4.0 (140)",
        "macOSVersion": "macOS 15.5",
    },
    "event": {
        "name": "translation_succeeded",
        "action": "rewrite",
        "route": "ai",
        "provider": "openai",
        "direction": "chinese_to_english",
        "style": "natural",
        "licenseTier": "free",
    },
}


class TelemetryCaptureValidationTests(unittest.TestCase):
    def test_accepts_valid_payload(self):
        validate_payload(VALID_PAYLOAD)

    def test_rejects_unknown_top_level_fields(self):
        payload = dict(VALID_PAYLOAD, ip="127.0.0.1")

        with self.assertRaisesRegex(ValueError, "unknown top-level field"):
            validate_payload(payload)

    def test_rejects_forbidden_private_fields_anywhere(self):
        payload = {
            **VALID_PAYLOAD,
            "event": {
                **VALID_PAYLOAD["event"],
                "sourceText": "好好学习",
            },
        }

        with self.assertRaisesRegex(ValueError, "forbidden field"):
            validate_payload(payload)

    def test_rejects_invalid_event_name(self):
        payload = {
            **VALID_PAYLOAD,
            "event": {
                **VALID_PAYLOAD["event"],
                "name": "raw_text_uploaded",
            },
        }

        with self.assertRaisesRegex(ValueError, "invalid event.name"):
            validate_payload(payload)


if __name__ == "__main__":
    unittest.main()
