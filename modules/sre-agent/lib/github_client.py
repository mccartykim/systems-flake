"""SRE Agent GitHub client — creates issues in mccartykim/homelab-incidents.

Idempotent: checks local issues.jsonl for existing open issues with the same
fingerprint before creating. Falls back gracefully on API failures.
"""
import hashlib
import json
import os
import re
import urllib.request
from datetime import datetime, timezone
from typing import Optional, Tuple


def _canonicalize_instance(instance: str) -> str:
    """Normalize instance labels for stable fingerprints.

    Strips port numbers and redacts known internal IP patterns
    so that fingerprints match regardless of whether the alert
    was redacted before filing.
    """
    # Strip port suffix (:9100, :9090, etc.)
    host = instance.rsplit(":", 1)[0] if ":" in instance else instance
    # Redact known internal IP ranges
    host = re.sub(
        r"\b(?:10\.100\.\d+\.\d+|192\.168\.\d+\.\d+|100\.64\.\d+\.\d+)\b",
        "[REDACTED-IP]",
        host,
    )
    return host


def _fingerprint(alertname: str, instance: str) -> str:
    """Generate a stable fingerprint from alertname + canonicalized instance."""
    raw = f"{alertname}|{_canonicalize_instance(instance)}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def _check_existing(state_dir: str, alertname: str, instance: str) -> Optional[str]:
    """Check if an open issue already exists for this fingerprint. Returns URL or None."""
    issues_path = os.path.join(state_dir, "issues.jsonl")
    if not os.path.exists(issues_path):
        return None
    fp = _fingerprint(alertname, instance)
    try:
        with open(issues_path) as f:
            for line in f:
                entry = json.loads(line.strip())
                if entry.get("fingerprint") == fp and entry.get("state") == "open":
                    return entry["url"]
    except (json.JSONDecodeError, KeyError, OSError):
        pass
    return None


def _record_issue(state_dir: str, alertname: str, instance: str, url: str):
    """Append an issue record to the local issues file."""
    issues_path = os.path.join(state_dir, "issues.jsonl")
    entry = {
        "fingerprint": _fingerprint(alertname, instance),
        "url": url,
        "state": "open",
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    try:
        with open(issues_path, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        pass


def create_issue(
    title: str,
    body: str,
    alertname: str,
    instance: str,
) -> Tuple[Optional[str], bool]:
    """Create a GitHub issue if one doesn't already exist.

    Returns (issue_url, was_created) — was_created is True if a new issue
    was created, False if an existing open issue was found. Returns
    (None, False) on failure.
    """
    state_dir = os.environ.get("STATE_DIR", "/var/lib/sre-agent")
    token_file = os.environ.get("GITHUB_TOKEN_FILE", "")
    repo = os.environ.get("GITHUB_REPO", "mccartykim/homelab-incidents")

    # Check for existing open issue (idempotency)
    existing = _check_existing(state_dir, alertname, instance)
    if existing:
        return (existing, False)

    # Read GitHub token
    if not token_file or not os.path.exists(token_file):
        return (None, False)
    try:
        with open(token_file) as f:
            token = f.read().strip()
    except OSError:
        return (None, False)
    if not token or token.startswith("PLACEHOLDER"):
        return (None, False)

    # Create issue via GitHub API
    url = f"https://api.github.com/repos/{repo}/issues"
    payload = json.dumps({
        "title": title,
        "body": body,
        "labels": ["sre-agent"],
    }).encode()

    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"token {token}",
            "Content-Type": "application/json",
            "Accept": "application/vnd.github.v3+json",
        },
    )

    try:
        resp = urllib.request.urlopen(req, timeout=30)
        data = json.loads(resp.read().decode())
        issue_url = data.get("html_url", "")
        if issue_url:
            _record_issue(state_dir, alertname, instance, issue_url)
        return (issue_url or None, True) if issue_url else (None, False)
    except Exception:
        return (None, False)


def close_issue(alertname: str, instance: str) -> Optional[str]:
    """Close the GitHub issue for this alert fingerprint. Returns the issue URL or None."""
    state_dir = os.environ.get("STATE_DIR", "/var/lib/sre-agent")
    token_file = os.environ.get("GITHUB_TOKEN_FILE", "")
    repo = os.environ.get("GITHUB_REPO", "mccartykim/homelab-incidents")

    # Find the open issue in our local log
    issues_path = os.path.join(state_dir, "issues.jsonl")
    fp = _fingerprint(alertname, instance)
    issue_url = None
    issue_number = None

    if not os.path.exists(issues_path):
        return None

    try:
        with open(issues_path) as f:
            for line in f:
                entry = json.loads(line.strip())
                if entry.get("fingerprint") == fp and entry.get("state") == "open":
                    issue_url = entry["url"]
                    break
    except (json.JSONDecodeError, KeyError, OSError):
        return None

    if not issue_url:
        return None

    # Extract issue number from URL (e.g., https://github.com/mccartykim/homelab-incidents/issues/2)
    try:
        issue_number = int(issue_url.rstrip("/").split("/")[-1])
    except (ValueError, IndexError):
        return None

    # Read GitHub token
    if not token_file or not os.path.exists(token_file):
        return None
    try:
        with open(token_file) as f:
            token = f.read().strip()
    except OSError:
        return None
    if not token or token.startswith("PLACEHOLDER"):
        return None

    # Close issue via GitHub API
    url = f"https://api.github.com/repos/{repo}/issues/{issue_number}"
    payload = json.dumps({"state": "closed"}).encode()
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"token {token}",
            "Content-Type": "application/json",
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "sre-agent/1.0",
        },
        method="PATCH",
    )

    try:
        urllib.request.urlopen(req, timeout=30)
        _update_issue_state(state_dir, fp, "closed")
        return issue_url
    except Exception:
        return None


def _update_issue_state(state_dir: str, fingerprint: str, new_state: str):
    """Update the state of an issue record in the local log."""
    issues_path = os.path.join(state_dir, "issues.jsonl")
    if not os.path.exists(issues_path):
        return
    try:
        with open(issues_path) as f:
            lines = f.readlines()
        updated = []
        for line in lines:
            entry = json.loads(line.strip())
            if entry.get("fingerprint") == fingerprint and entry.get("state") == "open":
                entry["state"] = new_state
                entry["closed_at"] = datetime.now(timezone.utc).isoformat()
            updated.append(json.dumps(entry))
        with open(issues_path, "w") as f:
            f.write("\n".join(updated) + "\n")
    except (json.JSONDecodeError, KeyError, OSError):
        pass
