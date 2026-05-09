"""Tests for sre_agent.discord_bot — fail-first TDD.

Phase 1.5 scope: /status command queries Prometheus and posts a rich embed.
Phase 2 will add /investigate.

Run with: python3 -m pytest modules/sre-agent/tests/test_discord_bot.py -v
"""
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

# discord.py may not be installed in test env — mock it
sys.modules["discord"] = MagicMock()
sys.modules["discord.app_commands"] = MagicMock()

from discord_bot import format_alert_embed, fetch_alerts


class TestFormatAlertEmbed(unittest.TestCase):
    """format_alert_embed should produce a Discord-friendly embed dict from alert data."""

    def test_single_alert(self):
        alerts = [
            {
                "labels": {"alertname": "NodeExporterDown", "severity": "critical", "instance": "10.100.0.50:9100"},
                "state": "firing",
                "annotations": {"summary": "Node exporter on 10.100.0.50 is down"},
            }
        ]
        embed = format_alert_embed(alerts)
        self.assertEqual(embed["title"], "SRE Alerts (1 active)")
        self.assertEqual(len(embed["fields"]), 1)
        self.assertIn("NodeExporterDown", embed["fields"][0]["name"])

    def test_empty_alerts(self):
        embed = format_alert_embed([])
        self.assertEqual(embed["title"], "SRE Alerts")
        self.assertIn("No active alerts", embed["description"])

    def test_redaction_in_embed(self):
        """IPs should be redacted in embeds; hostnames preserved for readability."""
        alerts = [
            {
                "labels": {"alertname": "TestAlert", "instance": "10.100.0.50:9090"},
                "state": "firing",
                "annotations": {"summary": "Service on maitred failed"},
            }
        ]
        embed = format_alert_embed(alerts)
        # IPs should be redacted
        for field in embed["fields"]:
            self.assertNotIn("10.100.0.50", field.get("value", ""))
        # Hostnames should be preserved for SRE readability
        self.assertTrue(
            any("maitred" in field.get("value", "") for field in embed["fields"])
        )

    def test_max_embeds_limit(self):
        """Discord limits embeds to 25 fields — truncate beyond that."""
        alerts = [{"labels": {"alertname": f"Alert{i}"}, "state": "firing"} for i in range(30)]
        embed = format_alert_embed(alerts)
        self.assertLessEqual(len(embed["fields"]), 25)


class TestFetchAlerts(unittest.TestCase):
    """fetch_alerts should query Prometheus /api/v1/alerts and return parsed data."""

    @patch("discord_bot.urllib.request.urlopen")
    def test_successful_fetch(self, mock_urlopen):
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "status": "success",
            "data": {"alerts": [
                {"labels": {"alertname": "TestAlert"}, "state": "firing"},
            ]},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        result = fetch_alerts("http://prometheus:9090")
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["labels"]["alertname"], "TestAlert")

    @patch("discord_bot.urllib.request.urlopen")
    def test_failure_returns_empty(self, mock_urlopen):
        """If Prometheus is unreachable, return empty list."""
        mock_urlopen.side_effect = Exception("connection refused")
        result = fetch_alerts("http://unreachable:9090")
        self.assertEqual(result, [])


if __name__ == "__main__":
    unittest.main()