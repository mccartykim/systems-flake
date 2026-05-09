"""SRE Agent Alertmanager silence client — auto-mute noise/info alerts.

Creates silences in Alertmanager so that noise-classified alerts stop
firing for a configurable duration. Only silences severity=noise and
severity=info alerts; never silences warning or critical.
"""
import json
import os
import urllib.request
from datetime import datetime, timezone, timedelta


def _env(key, default=""):
    return os.environ.get(key, default)


def _silence_url():
    """Get the Alertmanager silence API URL from env or default."""
    return _env("SILENCE_URL", "http://10.100.0.1:9093/api/v2/silences")


def list_silences(silence_url=None):
    """Fetch all silences from Alertmanager. Returns list of silence dicts."""
    url = silence_url or _silence_url()
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        resp = urllib.request.urlopen(req, timeout=10)
        data = json.loads(resp.read().decode())
        if isinstance(data, list):
            return data
        return []
    except Exception:
        return []


def check_existing_silence(alertname, instance, silence_url=None):
    """Check if an active silence already exists for these matchers.

    Returns True if a matching active silence is found, False otherwise.
    """
    silences = list_silences(silence_url)
    for s in silences:
        if s.get("status", {}).get("state") != "active":
            continue
        matchers = s.get("matchers", [])
        # Check if all our matchers are present in the silence
        target_matchers = {"alertname": alertname}
        if instance:
            target_matchers["instance"] = instance

        matched = 0
        for name, value in target_matchers.items():
            for m in matchers:
                if m.get("name") == name and m.get("value") == value and not m.get("isRegex", False):
                    matched += 1
                    break
        if matched == len(target_matchers):
            return True
    return False


def create_silence(alertname, instance="", duration_hours=4, created_by="sre-agent",
                   comment="", silence_url=None):
    """Create an Alertmanager silence for matching alerts.

    Args:
        alertname: The alert name to match.
        instance: The instance to match (empty string = match all instances).
        duration_hours: How long to silence (default 4h, matching Alertmanager repeat_interval).
        created_by: Creator string for the silence.
        comment: Optional comment for the silence.
        silence_url: Override for the Alertmanager API URL.

    Returns:
        The silence ID string, or None on failure.
    """
    url = silence_url or _silence_url()

    matchers = [
        {"name": "alertname", "value": alertname, "isRegex": False},
    ]
    if instance:
        matchers.append({"name": "instance", "value": instance, "isRegex": False})

    starts_at = datetime.now(timezone.utc).isoformat()
    ends_at = (datetime.now(timezone.utc) + timedelta(hours=duration_hours)).isoformat()

    payload = json.dumps({
        "matchers": matchers,
        "startsAt": starts_at,
        "endsAt": ends_at,
        "createdBy": created_by,
        "comment": comment or f"Auto-silenced by sre-agent: {alertname}",
    }).encode()

    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json", "User-Agent": "sre-agent/1.0"},
    )

    try:
        resp = urllib.request.urlopen(req, timeout=10)
        data = json.loads(resp.read().decode())
        return data.get("silenceID")
    except Exception:
        return None


def maybe_silence(alertname, instance="", duration_hours=4, silence_url=None):
    """Create a silence only if one doesn't already exist.

    Returns the silence ID if created, None if already silenced or on failure.
    """
    if check_existing_silence(alertname, instance, silence_url):
        return None
    return create_silence(alertname, instance, duration_hours, silence_url=silence_url)