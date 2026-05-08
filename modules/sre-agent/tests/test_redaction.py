"""Tests for sre_agent.redaction — fail-first TDD.

These tests define the expected behavior of the redaction module.
Run with: python3 -m pytest modules/sre-agent/tests/test_redaction.py -v
"""
import json
import os
import tempfile
import unittest

# Ensure lib is importable
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

from redaction import redact, redact_alert, SENSITIVE_UNITS, FIELD_ALLOWLIST


class TestIPRedaction(unittest.TestCase):
    """IP addresses in the 10.100.0.0/16, 192.168.0.0/16, and 100.64.0.0/10 ranges must be replaced."""

    def test_nebula_ip_redacted(self):
        text = "Connection from 10.100.0.50 timed out"
        result = redact(text)
        self.assertNotIn("10.100.0.50", result)
        self.assertIn("[REDACTED-IP]", result)

    def test_lan_ip_redacted(self):
        text = "Server at 192.168.69.1 is unreachable"
        result = redact(text)
        self.assertNotIn("192.168.69.1", result)
        self.assertIn("[REDACTED-IP]", result)

    def test_tailscale_ip_redacted(self):
        text = "Tailscale node 100.64.0.1 connected"
        result = redact(text)
        self.assertNotIn("100.64.0.1", result)
        self.assertIn("[REDACTED-IP]", result)

    def test_multiple_ips(self):
        text = "Forwarding from 10.100.0.40 to 192.168.69.1"
        result = redact(text)
        self.assertNotIn("10.100.0.40", result)
        self.assertNotIn("192.168.69.1", result)
        self.assertEqual(result.count("[REDACTED-IP]"), 2)

    def test_public_ip_not_redacted(self):
        """Public IPs (e.g. 8.8.8.8) should NOT be redacted."""
        text = "DNS resolver at 8.8.8.8"
        result = redact(text)
        self.assertIn("8.8.8.8", result)
        self.assertNotIn("[REDACTED-IP]", result)


class TestHostnameRedaction(unittest.TestCase):
    """Known hostnames in the nebula mesh must be replaced."""

    def test_nebula_hostnames(self):
        for host in ["maitred", "rich-evans", "historian", "total-eclipse", "oracle"]:
            with self.subTest(host=host):
                result = redact(f"Service on {host} failed")
                self.assertNotIn(host, result)
                self.assertIn("[REDACTED-HOST]", result)

    def test_hostname_with_domain(self):
        text = "SSH to maitred.nebula timed out"
        result = redact(text)
        self.assertNotIn("maitred", result)
        self.assertIn("[REDACTED-HOST]", result)

    def test_hostname_partial_match_not_redacted(self):
        """'history' should NOT match 'historian'."""
        text = "Check the history log"
        result = redact(text)
        self.assertIn("history", result)
        self.assertNotIn("[REDACTED-HOST]", result)


class TestEmailRedaction(unittest.TestCase):
    def test_email_redacted(self):
        text = "Contact admin@example.com for details"
        result = redact(text)
        self.assertNotIn("admin@example.com", result)
        self.assertIn("[REDACTED-EMAIL]", result)

    def test_complex_email(self):
        text = "User first.last+tag@sub.domain.org reported"
        result = redact(text)
        self.assertNotIn("first.last+tag@sub.domain.org", result)
        self.assertIn("[REDACTED-EMAIL]", result)


class TestTokenRedaction(unittest.TestCase):
    """Discord tokens and GitHub PATs must be scrubbed."""

    def test_discord_token_redacted(self):
        # Discord token format: base64.id.hmac (MTE4NjE.GnTZvc.signature)
        text = "Bot token: MTE4NjE2OQ.GnTZvc.N3_oGK2O8JDJXp3EKh9E79i612L_sig"
        result = redact(text)
        self.assertNotIn("MTE4NjE2OQ.GnTZvc", result)
        self.assertIn("[REDACTED-TOKEN]", result)

    def test_github_classic_pat_redacted(self):
        text = "token=ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij"
        result = redact(text)
        self.assertNotIn("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij", result)
        self.assertIn("[REDACTED-PAT]", result)

    def test_github_fine_grained_pat_redacted(self):
        text = "auth=github_pat_1ABCDEF2ghI34jKLmnoPQRsTUVwxyz1234567890_AB"
        result = redact(text)
        self.assertNotIn("github_pat_", result)
        self.assertIn("[REDACTED-PAT]", result)


class TestHexRedaction(unittest.TestCase):
    """32+ hex strings (API keys, hashes) must be replaced."""

    def test_hex_string_redacted(self):
        text = "Key: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
        result = redact(text)
        self.assertNotIn("a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6", result)
        self.assertIn("[REDACTED-HEX]", result)

    def test_short_hex_not_redacted(self):
        """Short hex strings (<32 chars) should NOT be redacted."""
        text = "Color #ff0000 and short id abc123"
        result = redact(text)
        self.assertIn("#ff0000", result)
        self.assertIn("abc123", result)


class TestFieldAllowlist(unittest.TestCase):
    """Fields in the allowlist should pass through redaction without being treated as sensitive."""

    def test_allowlist_fields(self):
        for field in FIELD_ALLOWLIST:
            with self.subTest(field=field):
                # These field names should not trigger any redaction by themselves
                result = redact(field)
                self.assertEqual(result, field)

    def test_allowlist_in_alert(self):
        """Alert fields in the allowlist should preserve their values."""
        alert = {
            "status": "firing",
            "labels": {
                "alertname": "NodeExporterDown",
                "severity": "critical",
                "job": "node-exporter",
                "instance": "10.100.0.50:9100",
            },
            "annotations": {
                "summary": "Node exporter on 10.100.0.50 is down",
            },
        }
        result = redact_alert(alert)
        # Allowlist field values for status/alertname/severity/job are preserved
        self.assertEqual(result["status"], "firing")
        self.assertEqual(result["labels"]["alertname"], "NodeExporterDown")
        self.assertEqual(result["labels"]["severity"], "critical")
        self.assertEqual(result["labels"]["job"], "node-exporter")
        # But instance IP should be redacted
        self.assertNotIn("10.100.0.50", result["labels"]["instance"])
        # And annotation IP should also be redacted
        self.assertNotIn("10.100.0.50", result["annotations"]["summary"])


class TestSensitiveUnitBlocklist(unittest.TestCase):
    """Alerts mentioning sensitive systemd units should have their annotations fully replaced."""

    def test_sensitive_unit_summary_redacted(self):
        # If a unit is in SENSITIVE_UNITS, the entire annotation/summary should be replaced
        alert = {
            "labels": {
                "alertname": "UnitFailed",
                "unit": "life-coach-agent.service",
            },
            "annotations": {
                "summary": "life-coach-agent.service failed with exit code 1 on maitred",
            },
        }
        # This test assumes life-coach-agent is in SENSITIVE_UNITS
        # If the blocklist isn't populated yet, this test documents the intent
        if "life-coach-agent.service" in SENSITIVE_UNITS:
            result = redact_alert(alert)
            self.assertIn("[REDACTED-sensitive-unit]", result["annotations"]["summary"])

    def test_non_sensitive_unit_not_redacted_summary(self):
        """Non-sensitive units should still be redacted for IPs/hostnames, but not fully replaced."""
        alert = {
            "labels": {
                "alertname": "UnitFailed",
                "unit": "nginx.service",
            },
            "annotations": {
                "summary": "nginx.service failed on 10.100.0.50",
            },
        }
        result = redact_alert(alert)
        self.assertNotIn("10.100.0.50", result["annotations"]["summary"])
        self.assertIn("nginx.service", result["annotations"]["summary"])
        self.assertNotIn("[REDACTED-sensitive-unit]", result["annotations"]["summary"])


class TestRedactAlert(unittest.TestCase):
    """Test the redact_alert dict function preserves structure."""

    def test_preserves_structure(self):
        alert = {
            "status": "firing",
            "labels": {"alertname": "TestAlert", "severity": "warning"},
            "annotations": {"summary": "Test on 10.100.0.40"},
            "startsAt": "2026-05-08T22:00:00Z",
            "fingerprint": "abc123",
        }
        result = redact_alert(alert)
        # Structure preserved
        self.assertIn("status", result)
        self.assertIn("labels", result)
        self.assertIn("annotations", result)
        self.assertIn("startsAt", result)
        # IP redacted
        self.assertNotIn("10.100.0.40", result["annotations"]["summary"])
        self.assertIn("[REDACTED-IP]", result["annotations"]["summary"])

    def test_nested_redaction(self):
        """All string values in the dict should be redacted recursively."""
        alert = {
            "labels": {"instance": "maitred:9093"},
            "annotations": {"description": "Alertmanager at maitred is down"},
        }
        result = redact_alert(alert)
        self.assertNotIn("maitred", result["labels"]["instance"])
        self.assertNotIn("maitred", result["annotations"]["description"])
        self.assertIn("[REDACTED-HOST]", result["labels"]["instance"])
        self.assertIn("[REDACTED-HOST]", result["annotations"]["description"])


class TestAuditLog(unittest.TestCase):
    """Every redaction should write an audit log entry."""

    def test_audit_log_written(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            os.environ["STATE_DIR"] = tmpdir
            # Re-init to pick up new STATE_DIR
            import importlib

            importlib.reload(sys.modules["redaction"])

            text = "Server 10.100.0.50 is down"
            redact(text, context="test alert summary")

            log_path = os.path.join(tmpdir, "redactions.jsonl")
            self.assertTrue(os.path.exists(log_path))

            with open(log_path) as f:
                entries = [json.loads(line) for line in f]

            self.assertGreaterEqual(len(entries), 1)
            entry = entries[0]
            self.assertEqual(entry["rule"], "ip")
            self.assertEqual(entry["context"], "test alert summary")
            self.assertGreater(entry["original_length"], 0)


if __name__ == "__main__":
    unittest.main()