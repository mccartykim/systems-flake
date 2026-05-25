"""Tests for sre_agent.webhook — resolved alert handling.

Run with: python3 -m pytest modules/sre-agent/tests/test_webhook.py -v
"""
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from webhook import format_resolved


class TestFormatResolved(unittest.TestCase):
    """format_resolved should format resolved alerts for Discord."""

    def test_single_resolved_alert(self):
        payload = {
            "status": "resolved",
            "alerts": [{
                "status": "resolved",
                "labels": {"alertname": "NodeExporterDown", "instance": "10.100.0.50:9100"},
                "annotations": {"summary": "Node exporter down"},
            }],
        }
        result = format_resolved(payload)
        self.assertIn("[RESOLVED]", result)
        self.assertIn("NodeExporterDown", result)
        self.assertIn("resolved", result)

    def test_multiple_resolved_alerts(self):
        payload = {
            "status": "resolved",
            "alerts": [
                {
                    "status": "resolved",
                    "labels": {"alertname": "NodeExporterDown", "instance": "host1:9100"},
                },
                {
                    "status": "resolved",
                    "labels": {"alertname": "OllamaUnreachable", "instance": "host2:11434"},
                },
            ],
        }
        result = format_resolved(payload)
        self.assertIn("NodeExporterDown", result)
        self.assertIn("OllamaUnreachable", result)

    def test_resolved_alert_preserves_instance(self):
        payload = {
            "status": "resolved",
            "alerts": [{
                "status": "resolved",
                "labels": {"alertname": "TestAlert", "instance": "192.168.1.100:9090"},
            }],
        }
        result = format_resolved(payload)
        # Instance IP must reach Discord intact — no redaction
        self.assertIn("TestAlert", result)
        self.assertIn("192.168.1.100", result)


if __name__ == "__main__":
    unittest.main()