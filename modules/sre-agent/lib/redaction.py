"""SRE Agent redaction module — DEPRECATED.

No longer called from any production code path. IPs/hostnames are now sent
to Discord and the LLM unredacted (overseer rolled back the paranoia — the
filtered output was useless for observability). Retained so call sites can
be re-enabled quickly if the policy reverses.
"""
import json
import os
import re
from datetime import datetime, timezone

# --- Configuration ---

FIELD_ALLOWLIST = frozenset({
    "alertname",
    "severity",
    "status",
    "expr",
    "for",
    "job",
})

SENSITIVE_UNITS = frozenset({
    "life-coach-agent.service",
    "org-crm-agent.service",
})

# Regex rules: (compiled_pattern, replacement_tag, rule_name)
_REGEX_RULES = [
    # Internal IP addresses (nebula, LAN, tailscale)
    (
        re.compile(
            r"\b(?:10\.100\.\d+\.\d+|192\.168\.\d+\.\d+|100\.64\.\d+\.\d+)\b"
        ),
        "[REDACTED-IP]",
        "ip",
    ),
    # Email addresses
    (
        re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z0-9]{2,}\b"),
        "[REDACTED-EMAIL]",
        "email",
    ),
    # Discord tokens (base64.id.hmac pattern — three dot-separated segments)
    (
        re.compile(r"\b[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{20,}\b"),
        "[REDACTED-TOKEN]",
        "token",
    ),
    # GitHub PATs
    (
        re.compile(r"\bghp_[A-Za-z0-9]{36}\b"),
        "[REDACTED-PAT]",
        "pat",
    ),
    (
        re.compile(r"\bgithub_pat_[A-Za-z0-9_]{40,}\b"),
        "[REDACTED-PAT]",
        "pat",
    ),
    # 32+ hex strings (API keys, hashes)
    (
        re.compile(r"\b[a-f0-9]{32,}\b"),
        "[REDACTED-HEX]",
        "hex",
    ),
]


def _get_state_dir():
    return os.environ.get("STATE_DIR", "/var/lib/sre-agent")


def _audit_log(rule, original_length, context):
    """Append one line to the redactions audit log."""
    state_dir = _get_state_dir()
    log_path = os.path.join(state_dir, "redactions.jsonl")
    try:
        entry = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "rule": rule,
            "original_length": original_length,
            "context": context,
        }
        with open(log_path, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        # Audit logging must never crash the agent
        pass


def redact(text: str, context: str = "") -> str:
    """Redact PII from a string.

    Args:
        text: The text to redact.
        context: Description of where the text came from (for audit log).

    Returns:
        The redacted string.
    """
    original_length = len(text)
    result = text
    for pattern, replacement, rule_name in _REGEX_RULES:
        if pattern.search(result):
            _audit_log(rule_name, original_length, context)
            result = pattern.sub(replacement, result)
    return result


def redact_alert(alert: dict) -> dict:
    """Redact an entire Alertmanager alert dict, preserving structure.

    Allowlist fields pass through without redaction of their values.
    Sensitive unit names cause full annotation replacement.
    All other string values are redacted for IPs, hostnames, tokens, etc.
    """
    result = {}

    # Check if this alert mentions a sensitive unit
    labels = alert.get("labels", {})
    unit = labels.get("unit", "")
    is_sensitive = unit in SENSITIVE_UNITS

    for key, value in alert.items():
        if isinstance(value, dict):
            result[key] = _redact_dict(value, key, is_sensitive)
        elif isinstance(value, str):
            if key in FIELD_ALLOWLIST:
                result[key] = value
            else:
                result[key] = redact(value, context=f"alert {key}")
        else:
            result[key] = value

    return result


def _redact_dict(d: dict, parent_key: str = "", is_sensitive: bool = False) -> dict:
    """Redact all string values in a dict, respecting allowlist and sensitive units."""
    result = {}
    for key, value in d.items():
        if isinstance(value, dict):
            result[key] = _redact_dict(value, key, is_sensitive)
        elif isinstance(value, str):
            if is_sensitive and parent_key == "annotations":
                # Full replacement for sensitive unit annotations
                result[key] = "[REDACTED-sensitive-unit]"
            else:
                result[key] = redact(value, context=f"alert {parent_key}.{key}")
        else:
            result[key] = value
    return result