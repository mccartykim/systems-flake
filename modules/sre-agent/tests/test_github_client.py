"""Tests for sre_agent.github_client — fail-first TDD.

Run with: python3 -m pytest modules/sre-agent/tests/test_github_client.py -v
"""
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from github_client import create_issue, _fingerprint, _check_existing


class TestFingerprint(unittest.TestCase):
    """Fingerprinting should produce stable hashes for alert+instance pairs."""

    def test_deterministic(self):
        fp1 = _fingerprint("NodeExporterDown", "10.100.0.50:9100")
        fp2 = _fingerprint("NodeExporterDown", "10.100.0.50:9100")
        self.assertEqual(fp1, fp2)

    def test_different_alerts_different_fingerprints(self):
        fp1 = _fingerprint("NodeExporterDown", "10.100.0.50:9100")
        fp2 = _fingerprint("OllamaUnreachable", "10.100.0.6:11434")
        self.assertNotEqual(fp1, fp2)


class TestCheckExisting(unittest.TestCase):
    """_check_existing should find matching open issues in the local file."""

    def test_no_existing_issue(self):
        """If no issues.jsonl exists, return None."""
        with tempfile.TemporaryDirectory() as tmpdir:
            result = _check_existing(tmpdir, "NodeExporterDown", "host:9100")
            self.assertIsNone(result)

    def test_existing_open_issue(self):
        """If a matching open issue exists, return its URL."""
        with tempfile.TemporaryDirectory() as tmpdir:
            issues_path = os.path.join(tmpdir, "issues.jsonl")
            with open(issues_path, "w") as f:
                f.write(json.dumps({
                    "fingerprint": _fingerprint("NodeExporterDown", "host:9100"),
                    "url": "https://github.com/mccartykim/homelab-incidents/issues/1",
                    "state": "open",
                }) + "\n")
            result = _check_existing(tmpdir, "NodeExporterDown", "host:9100")
            self.assertEqual(result, "https://github.com/mccartykim/homelab-incidents/issues/1")

    def test_closed_issue_not_matched(self):
        """Closed issues should not prevent creating a new one."""
        with tempfile.TemporaryDirectory() as tmpdir:
            issues_path = os.path.join(tmpdir, "issues.jsonl")
            with open(issues_path, "w") as f:
                f.write(json.dumps({
                    "fingerprint": _fingerprint("NodeExporterDown", "host:9100"),
                    "url": "https://github.com/mccartykim/homelab-incidents/issues/1",
                    "state": "closed",
                }) + "\n")
            result = _check_existing(tmpdir, "NodeExporterDown", "host:9100")
            self.assertIsNone(result)


class TestCreateIssue(unittest.TestCase):
    """create_issue should POST to GitHub API with proper auth."""

    @patch("github_client.urllib.request.urlopen")
    def test_create_issue_success(self, mock_urlopen):
        """Successful issue creation returns URL."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "html_url": "https://github.com/mccartykim/homelab-incidents/issues/42",
            "number": 42,
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        with tempfile.TemporaryDirectory() as tmpdir:
            # Create fake token file
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test123456789012345678901234567890")

            os.environ["STATE_DIR"] = tmpdir
            os.environ["GITHUB_TOKEN_FILE"] = token_file
            os.environ["GITHUB_REPO"] = "mccartykim/homelab-incidents"

            url = create_issue(
                title="[SRE] NodeExporterDown on host",
                body="## Alert\n\nNodeExporterDown on host:9100\n\nSeverity: critical",
                alertname="NodeExporterDown",
                instance="host:9100",
            )
            self.assertEqual(url, "https://github.com/mccartykim/homelab-incidents/issues/42")

            # Verify request had proper auth
            req = mock_urlopen.call_args[0][0]
            self.assertIn("Authorization", req.headers)
            self.assertTrue(req.headers["Authorization"].startswith("token "))

            # Verify local issues file was written
            issues_path = os.path.join(tmpdir, "issues.jsonl")
            self.assertTrue(os.path.exists(issues_path))

    @patch("github_client.urllib.request.urlopen")
    def test_create_issue_idempotent(self, mock_urlopen):
        """If an open issue already exists, don't create a new one."""
        with tempfile.TemporaryDirectory() as tmpdir:
            os.environ["STATE_DIR"] = tmpdir
            # Pre-populate the issues file with an open issue
            issues_path = os.path.join(tmpdir, "issues.jsonl")
            with open(issues_path, "w") as f:
                f.write(json.dumps({
                    "fingerprint": _fingerprint("NodeExporterDown", "host:9100"),
                    "url": "https://github.com/mccartykim/homelab-incidents/issues/1",
                    "state": "open",
                }) + "\n")

            result = create_issue(
                title="[SRE] NodeExporterDown",
                body="test",
                alertname="NodeExporterDown",
                instance="host:9100",
            )
            # Should return existing URL without making an API call
            self.assertEqual(result, "https://github.com/mccartykim/homelab-incidents/issues/1")
            mock_urlopen.assert_not_called()

    @patch("github_client.urllib.request.urlopen")
    def test_create_issue_auth_from_token_file(self, mock_urlopen):
        """Token should be read from GITHUB_TOKEN_FILE, not hardcoded."""
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps({
            "html_url": "https://github.com/mccartykim/homelab-incidents/issues/5",
            "number": 5,
        }).encode()
        mock_response.__enter__ = lambda s: s
        mock_response.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_response

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_specific_token_123456789012345678")

            os.environ["STATE_DIR"] = tmpdir
            os.environ["GITHUB_TOKEN_FILE"] = token_file
            os.environ["GITHUB_REPO"] = "mccartykim/homelab-incidents"

            create_issue(
                title="Test",
                body="test",
                alertname="TestAlert",
                instance="host:9090",
            )
            req = mock_urlopen.call_args[0][0]
            self.assertEqual(req.headers["Authorization"], "token ghp_specific_token_123456789012345678")

    @patch("github_client.urllib.request.urlopen")
    def test_create_issue_api_failure(self, mock_urlopen):
        """If GitHub API fails, return None."""
        mock_urlopen.side_effect = Exception("API error")

        with tempfile.TemporaryDirectory() as tmpdir:
            token_file = os.path.join(tmpdir, "gh-token")
            with open(token_file, "w") as f:
                f.write("ghp_test_token_1234567890123456789012")

            os.environ["STATE_DIR"] = tmpdir
            os.environ["GITHUB_TOKEN_FILE"] = token_file
            os.environ["GITHUB_REPO"] = "mccartykim/homelab-incidents"

            result = create_issue(
                title="Test",
                body="test",
                alertname="TestAlert",
                instance="host:9090",
            )
            self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()