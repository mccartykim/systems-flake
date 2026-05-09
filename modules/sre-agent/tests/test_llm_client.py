"""Tests for sre_agent.llm_client — fail-first TDD.

Run with: python3 -m pytest modules/sre-agent/tests/test_llm_client.py -v
"""
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from llm_client import triage, TriageResult, parse_freeform_response


class TestTriageResult(unittest.TestCase):
    """TriageResult dataclass holds structured LLM output."""

    def test_from_dict(self):
        data = {
            "severity": "warning",
            "cause": "Disk full on host",
            "action": "Clear old logs",
            "file_issue": True,
            "issue_title": "Disk full on [REDACTED-HOST]",
        }
        result = TriageResult.from_dict(data)
        self.assertEqual(result.severity, "warning")
        self.assertEqual(result.cause, "Disk full on host")
        self.assertEqual(result.action, "Clear old logs")
        self.assertTrue(result.file_issue)
        self.assertEqual(result.issue_title, "Disk full on [REDACTED-HOST]")

    def test_defaults(self):
        result = TriageResult.from_dict({"severity": "info"})
        self.assertEqual(result.severity, "info")
        self.assertFalse(result.file_issue)
        self.assertEqual(result.issue_title, "")

    def test_uppercase_keys(self):
        """LLM with format:json returns uppercase keys (SEVERITY, CAUSE, etc.)."""
        data = {
            "SEVERITY": "noise",
            "CAUSE": "Test alert",
            "ACTION": "Acknowledge",
            "FILE_ISSUE": "no",
            "ISSUE_TITLE": "",
            "SILENCE": "4",
        }
        result = TriageResult.from_dict(data)
        self.assertEqual(result.severity, "noise")
        self.assertEqual(result.cause, "Test alert")
        self.assertEqual(result.action, "Acknowledge")
        self.assertFalse(result.file_issue)
        self.assertEqual(result.silence_hours, 4)

    def test_file_issue_string_yes(self):
        """file_issue may come as string 'yes'/'no' from LLM."""
        data = {"severity": "critical", "cause": "", "action": "", "FILE_ISSUE": "yes"}
        result = TriageResult.from_dict(data)
        self.assertTrue(result.file_issue)

    def test_silence_hours_mapping(self):
        """SILENCE key should map to silence_hours."""
        data = {"severity": "info", "cause": "", "action": "", "silence": 2}
        result = TriageResult.from_dict(data)
        self.assertEqual(result.silence_hours, 2)


class TestParseFreeformResponse(unittest.TestCase):
    """Free-form text parsing extracts SEVERITY/CAUSE/ACTION/FILE_ISSUE/ISSUE_TITLE lines."""

    def test_full_response(self):
        text = """SEVERITY: warning
CAUSE: Disk full on host
ACTION: Clear old logs
FILE_ISSUE: yes
ISSUE_TITLE: Disk full on [REDACTED-HOST]"""
        result = parse_freeform_response(text)
        self.assertEqual(result.severity, "warning")
        self.assertEqual(result.cause, "Disk full on host")
        self.assertEqual(result.action, "Clear old logs")
        self.assertTrue(result.file_issue)
        self.assertEqual(result.issue_title, "Disk full on [REDACTED-HOST]")

    def test_partial_response(self):
        text = """SEVERITY: critical
CAUSE: OOM killer invoked"""
        result = parse_freeform_response(text)
        self.assertEqual(result.severity, "critical")
        self.assertEqual(result.cause, "OOM killer invoked")
        self.assertFalse(result.file_issue)

    def test_case_insensitive(self):
        text = "severity: info\ncause: Normal fluctuation\naction: No action needed\nfile_issue: no"
        result = parse_freeform_response(text)
        self.assertEqual(result.severity, "info")
        self.assertEqual(result.cause, "Normal fluctuation")

    def test_empty_response(self):
        result = parse_freeform_response("")
        self.assertIsNone(result)

    def test_garbage_response(self):
        result = parse_freeform_response("I am a large language model and I cannot help with that")
        self.assertIsNone(result)


class TestTriageLocalOllama(unittest.TestCase):
    """triage() should call local Ollama first with format:json."""

    @patch("llm_client.urllib.request.urlopen")
    def test_local_ollama_json_mode(self, mock_urlopen):
        """Primary: local Ollama with format:json returns structured response."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": json.dumps({
                "severity": "warning",
                "cause": "Service degraded",
                "action": "Restart service",
                "file_issue": False,
                "issue_title": "",
            })},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        with tempfile.TemporaryDirectory() as tmpdir:
            os.environ["STATE_DIR"] = tmpdir
            result = triage(
                alertname="TestAlert",
                severity="warning",
                instance="host1:9090",
                summary="Service degraded",
            )
            self.assertIsNotNone(result)
            self.assertEqual(result.severity, "warning")
            self.assertEqual(result.cause, "Service degraded")

            # Verify the request used format:json
            call_args = mock_urlopen.call_args
            req = call_args[0][0]
            self.assertIn("format", req.data.decode())

    @patch("llm_client.urllib.request.urlopen")
    def test_local_ollama_timeout_falls_back(self, mock_urlopen):
        """If local Ollama times out, fall back to cloud."""
        # First call (local) raises timeout
        # Second call (cloud) succeeds
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": "SEVERITY: warning\nCAUSE: test\nACTION: none\nFILE_ISSUE: no"},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        call_count = [0]

        def side_effect(req, timeout=None):
            call_count[0] += 1
            if call_count[0] == 1:
                raise TimeoutError("local ollama timeout")
            return mock_response

        mock_urlopen.side_effect = side_effect

        with tempfile.TemporaryDirectory() as tmpdir:
            os.environ["STATE_DIR"] = tmpdir
            result = triage(
                alertname="TestAlert",
                severity="warning",
                instance="host1:9090",
                summary="test",
            )
            self.assertIsNotNone(result)
            self.assertEqual(result.severity, "warning")


class TestTriageCloudFallback(unittest.TestCase):
    """When local Ollama fails, cloud fallback should work."""

    @patch("llm_client.urllib.request.urlopen")
    def test_cloud_uses_bearer_auth(self, mock_urlopen):
        """Cloud fallback should include Authorization: Bearer header."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": "SEVERITY: info\nCAUSE: normal\nACTION: none\nFILE_ISSUE: no"},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)

        # Make local fail, cloud succeed
        call_count = [0]
        requests = []

        def side_effect(req, timeout=None):
            requests.append(req)
            call_count[0] += 1
            if call_count[0] <= 2:
                # Local retries fail
                raise ConnectionError("local down")
            # Cloud succeeds
            return mock_response

        mock_urlopen.side_effect = side_effect

        with tempfile.TemporaryDirectory() as tmpdir:
            os.environ["STATE_DIR"] = tmpdir
            # Create a fake API key file
            key_file = os.path.join(tmpdir, "ollama-key")
            with open(key_file, "w") as f:
                f.write("test-api-key-12345")
            os.environ["OLLAMA_CLOUD_KEY_FILE"] = key_file

            result = triage(
                alertname="TestAlert",
                severity="warning",
                instance="host1:9090",
                summary="test",
            )
            # Find the cloud request (URL contains ollama.com)
            cloud_reqs = [r for r in requests if "ollama.com" in r.full_url]
            self.assertGreaterEqual(len(cloud_reqs), 1, "No cloud request was made")
            req = cloud_reqs[0]
            self.assertIn("Authorization", req.headers)
            self.assertTrue(req.headers["Authorization"].startswith("Bearer "))


class TestTriageCache(unittest.TestCase):
    """LLM responses should be cached for deduplication."""

    @patch("llm_client.urllib.request.urlopen")
    def test_cache_hit(self, mock_urlopen):
        """Second triage call with same args should use cache."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "message": {"content": json.dumps({
                "severity": "warning",
                "cause": "cached cause",
                "action": "cached action",
                "file_issue": False,
                "issue_title": "",
            })},
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        with tempfile.TemporaryDirectory() as tmpdir:
            os.environ["STATE_DIR"] = tmpdir
            result1 = triage(
                alertname="TestAlert",
                severity="warning",
                instance="host1:9090",
                summary="test summary",
            )
            # Second call — should hit cache, not make another HTTP request
            result2 = triage(
                alertname="TestAlert",
                severity="warning",
                instance="host1:9090",
                summary="test summary",
            )
            self.assertEqual(result1.severity, result2.severity)
            # Should only have called urlopen once (cache hit on second call)
            self.assertEqual(mock_urlopen.call_count, 1)


class TestTriageFailure(unittest.TestCase):
    """If all LLM calls fail, triage should return None (Phase 0 fallback)."""

    @patch("llm_client.urllib.request.urlopen")
    def test_all_failures_return_none(self, mock_urlopen):
        """When both local and cloud fail, return None for Phase 0 fallback."""
        mock_urlopen.side_effect = ConnectionError("all endpoints down")

        with tempfile.TemporaryDirectory() as tmpdir:
            os.environ["STATE_DIR"] = tmpdir
            result = triage(
                alertname="TestAlert",
                severity="critical",
                instance="host1:9090",
                summary="everything is broken",
            )
            self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()