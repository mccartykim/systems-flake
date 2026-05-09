"""Tests for sre_agent.silence_client — fail-first TDD.

Phase 2A: Alertmanager silencing for noise/info alerts.

Run with: python3 -m pytest modules/sre-agent/tests/test_silence_client.py -v
"""
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from silence_client import create_silence, check_existing_silence, list_silences


class TestCreateSilence(unittest.TestCase):
    """create_silence should POST to Alertmanager /api/v2/silences."""

    @patch("silence_client.urllib.request.urlopen")
    def test_creates_silence_with_matchers(self, mock_urlopen):
        """Should create a silence matching alertname and instance."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps(
            {"silenceID": "abc123"}
        ).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        result = create_silence(
            alertname="NodeExporterDown",
            instance="10.100.0.50:9100",
            duration_hours=4,
            silence_url="http://alertmanager:9093/api/v2/silences",
        )
        self.assertEqual(result, "abc123")

        # Verify the request body
        call_args = mock_urlopen.call_args
        req = call_args[0][0]
        self.assertEqual(req.get_method(), "POST")
        self.assertIn("alertmanager:9093/api/v2/silences", req.full_url)

        body = json.loads(req.data.decode())
        self.assertEqual(body["matchers"][0]["name"], "alertname")
        self.assertEqual(body["matchers"][0]["value"], "NodeExporterDown")
        self.assertEqual(body["matchers"][0]["isRegex"], False)
        self.assertEqual(body["matchers"][1]["name"], "instance")
        self.assertEqual(body["matchers"][1]["value"], "10.100.0.50:9100")
        # endsAt should be an ISO timestamp ~4h from now
        self.assertTrue(body["endsAt"].startswith("202"), f"endsAt should be ISO timestamp: {body['endsAt']}")

    @patch("silence_client.urllib.request.urlopen")
    def test_creates_silence_without_instance(self, mock_urlopen):
        """Should create a silence matching only alertname if instance is empty."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps(
            {"silenceID": "def456"}
        ).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        result = create_silence(
            alertname="OllamaUnreachable",
            instance="",
            duration_hours=2,
            silence_url="http://alertmanager:9093/api/v2/silences",
        )
        self.assertEqual(result, "def456")

        body = json.loads(mock_urlopen.call_args[0][0].data.decode())
        self.assertEqual(len(body["matchers"]), 1)
        self.assertEqual(body["matchers"][0]["name"], "alertname")

    @patch("silence_client.urllib.request.urlopen")
    def test_failure_returns_none(self, mock_urlopen):
        """Should return None if Alertmanager is unreachable."""
        mock_urlopen.side_effect = Exception("connection refused")
        result = create_silence(
            alertname="TestAlert",
            instance="localhost:9090",
            silence_url="http://unreachable:9093/api/v2/silences",
        )
        self.assertIsNone(result)

    @patch("silence_client.urllib.request.urlopen")
    def test_uses_env_for_url(self, mock_urlopen):
        """Should read SILENCE_URL from environment."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps(
            {"silenceID": "env123"}
        ).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        with patch.dict(os.environ, {"SILENCE_URL": "http://custom:9093/api/v2/silences"}):
            result = create_silence(alertname="Test", instance="")
        self.assertEqual(result, "env123")
        req = mock_urlopen.call_args[0][0]
        self.assertIn("custom:9093", req.full_url)


class TestCheckExistingSilence(unittest.TestCase):
    """check_existing_silence should query Alertmanager for active silences."""

    @patch("silence_client.urllib.request.urlopen")
    def test_finds_existing_silence(self, mock_urlopen):
        """Should return True if an active silence exists for these matchers."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps([
            {
                "id": "existing123",
                "status": {"state": "active"},
                "matchers": [
                    {"name": "alertname", "value": "NodeExporterDown", "isRegex": False},
                    {"name": "instance", "value": "10.100.0.50:9100", "isRegex": False},
                ],
            }
        ]).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        result = check_existing_silence(
            alertname="NodeExporterDown",
            instance="10.100.0.50:9100",
            silence_url="http://alertmanager:9093/api/v2/silences",
        )
        self.assertTrue(result)

    @patch("silence_client.urllib.request.urlopen")
    def test_no_existing_silence(self, mock_urlopen):
        """Should return False if no matching silence exists."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps([]).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        result = check_existing_silence(
            alertname="NewAlert",
            instance="host:9090",
            silence_url="http://alertmanager:9093/api/v2/silences",
        )
        self.assertFalse(result)

    @patch("silence_client.urllib.request.urlopen")
    def test_expired_silence_not_counted(self, mock_urlopen):
        """Should not count expired silences as existing."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps([
            {
                "id": "expired123",
                "status": {"state": "expired"},
                "matchers": [
                    {"name": "alertname", "value": "TestAlert", "isRegex": False},
                ],
            }
        ]).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        result = check_existing_silence(
            alertname="TestAlert",
            instance="",
            silence_url="http://alertmanager:9093/api/v2/silences",
        )
        self.assertFalse(result)


class TestMaybeSilence(unittest.TestCase):
    """Integration test for the maybe_silence helper."""

    @patch("silence_client.check_existing_silence")
    @patch("silence_client.create_silence")
    def test_creates_silence_when_none_exists(self, mock_create, mock_check):
        """Should create a silence if none exists for this alert."""
        mock_check.return_value = False
        mock_create.return_value = "new123"
        from silence_client import maybe_silence
        result = maybe_silence(
            alertname="NoiseAlert",
            instance="host:9090",
            duration_hours=4,
            silence_url="http://am:9093/api/v2/silences",
        )
        self.assertEqual(result, "new123")

    @patch("silence_client.check_existing_silence")
    @patch("silence_client.create_silence")
    def test_skips_if_silence_exists(self, mock_create, mock_check):
        """Should not create a duplicate silence."""
        mock_check.return_value = True
        from silence_client import maybe_silence
        result = maybe_silence(
            alertname="NoiseAlert",
            instance="host:9090",
            duration_hours=4,
            silence_url="http://am:9093/api/v2/silences",
        )
        self.assertIsNone(result)
        mock_create.assert_not_called()


if __name__ == "__main__":
    unittest.main()