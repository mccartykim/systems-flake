"""SRE Agent GitHub client — creates issues in mccartykim/homelab-incidents.

Idempotent: checks local issues.jsonl for existing open issues with the same
fingerprint before creating. Falls back gracefully on API failures.
"""
import hashlib
import json
import os
import urllib.request
from datetime import datetime, timezone
from typing import Optional


def _fingerprint(alertname: str, instance: str) -> str:
    """Generate a stable fingerprint from alertname + instance."""
    raw = f"{alertname}|{instance}"
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
) -> Optional[str]:
    """Create a GitHub issue if one doesn't already exist. Returns issue URL or None on failure."""
    state_dir = os.environ.get("STATE_DIR", "/var/lib/sre-agent")
    token_file = os.environ.get("GITHUB_TOKEN_FILE", "")
    repo = os.environ.get("GITHUB_REPO", "mccartykim/homelab-incidents")

    # Check for existing open issue (idempotency)
    existing = _check_existing(state_dir, alertname, instance)
    if existing:
        return existing

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
        return issue_url or None
    except Exception:
        return None