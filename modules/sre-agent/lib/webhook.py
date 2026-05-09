"""SRE Agent Webhook Receiver — Alertmanager webhook HTTP server.

Receives alerts from Alertmanager, redacts PII, optionally runs LLM triage,
posts to Discord, and creates GitHub issues when appropriate.
"""
import http.server
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

# Add lib directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from redaction import redact, redact_alert


def _env(key, default=""):
    return os.environ.get(key, default)


def post_discord(msg):
    """Post a message to the configured Discord channel."""
    channel_id = _env("DISCORD_CHANNEL_ID")
    token_file = _env("DISCORD_TOKEN_FILE")

    if not channel_id or channel_id == "TODO":
        print(f"discord: no channel id configured, skipping: {msg}", file=sys.stderr)
        return
    try:
        with open(token_file) as f:
            token = f.read().strip()
        if not token or token.startswith("PLACEHOLDER"):
            print("discord: token is placeholder, skipping", file=sys.stderr)
            return
        data = json.dumps({"content": msg[:2000]}).encode()
        req = urllib.request.Request(
            f"https://discord.com/api/v10/channels/{channel_id}/messages",
            data=data,
            headers={"Authorization": f"Bot {token}", "Content-Type": "application/json", "User-Agent": "sre-agent/1.0"},
        )
        urllib.request.urlopen(req, timeout=10)
    except Exception as e:
        print(f"discord post failed: {e}", file=sys.stderr)


def format_alert(payload):
    """Format an Alertmanager webhook payload into a Discord-ready message."""
    status = payload.get("status", "unknown")
    alerts = payload.get("alerts", [])
    lines = [f"[{status.upper()}]"]
    for a in alerts:
        labels = a.get("labels", {})
        annotations = a.get("annotations", {})
        name = labels.get("alertname", "unknown")
        instance = labels.get("instance", "?")
        summary = annotations.get("summary", annotations.get("description", ""))
        # Redact PII before sending to Discord
        instance = redact(instance, context="alert instance")
        summary = redact(summary, context="alert annotation summary")
        lines.append(f"**{name}** ({instance}): {summary}")
    return "\n".join(lines)


def run_triage(alert):
    """Run LLM triage on a single alert dict. Returns TriageResult or None."""
    enable_llm = _env("ENABLE_LLM_TRIAGE", "false").lower() in ("true", "1", "yes")
    if not enable_llm:
        return None

    from llm_client import triage
    labels = alert.get("labels", {})
    annotations = alert.get("annotations", {})
    return triage(
        alertname=labels.get("alertname", "unknown"),
        severity=labels.get("severity", "unknown"),
        instance=labels.get("instance", "?"),
        summary=annotations.get("summary", annotations.get("description", "")),
    )


def maybe_file_issue(alert, triage_result):
    """Create a GitHub issue if triage recommends it. Returns issue URL or None."""
    if triage_result is None or not triage_result.file_issue:
        return None

    from github_client import create_issue
    from redaction import redact

    labels = alert.get("labels", {})
    title = triage_result.issue_title or f"[SRE] {labels.get('alertname', 'unknown')}"
    title = redact(title, context="issue title")

    annotations = alert.get("annotations", {})
    body_parts = [
        f"## Alert: {labels.get('alertname', 'unknown')}",
        f"**Severity:** {triage_result.severity}",
        f"**Instance:** {redact(labels.get('instance', '?'), context='issue instance')}",
        f"**Summary:** {redact(annotations.get('summary', ''), context='issue summary')}",
        "",
        "### LLM Triage",
        f"- **Cause:** {triage_result.cause}",
        f"- **Action:** {triage_result.action}",
    ]

    return create_issue(
        title=title,
        body="\n".join(body_parts),
        alertname=labels.get("alertname", "unknown"),
        instance=labels.get("instance", "?"),
    )


class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        state_dir = _env("STATE_DIR", "/var/lib/sre-agent")
        alerts_log = os.path.join(state_dir, "alerts.jsonl")

        # Log raw alert (with PII — internal log, not sent externally)
        with open(alerts_log, "a") as f:
            f.write(json.dumps({"ts": datetime.now(timezone.utc).isoformat(), **payload}) + "\n")

        # Format and redact for Discord
        msg = format_alert(payload)
        print(msg)
        post_discord(msg)

        # Optional LLM triage
        for alert in payload.get("alerts", []):
            redacted = redact_alert(alert)
            result = run_triage(redacted)
            if result:
                ts = datetime.now(timezone.utc).strftime("%H:%M UTC")
                triage_msg = (
                    f"[{ts}] **Triage:** {result.severity} | Cause: {result.cause} | Action: {result.action}"
                )
                if result.file_issue:
                    triage_msg += f" | Filing issue: {result.issue_title or 'yes'}"
                post_discord(triage_msg)

                # Maybe create a GitHub issue
                issue_url = maybe_file_issue(redacted, result)
                if issue_url:
                    ts = datetime.now(timezone.utc).strftime("%H:%M UTC")
                    post_discord(f"[{ts}] **Issue created:** {issue_url}")

                # Maybe silence noise/info alerts
                if result.silence_hours > 0 and result.severity in ("noise", "info"):
                    from silence_client import maybe_silence
                    labels = alert.get("labels", {})
                    silence_id = maybe_silence(
                        alertname=labels.get("alertname", "unknown"),
                        instance=labels.get("instance", ""),
                        duration_hours=result.silence_hours,
                    )
                    if silence_id:
                        ts = datetime.now(timezone.utc).strftime("%H:%M UTC")
                        post_discord(f"[{ts}] **Silenced:** {labels.get('alertname', 'unknown')} for {result.silence_hours}h (ID: {silence_id})")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')

    def log_message(self, fmt, *args):
        print(f"webhook: {fmt % args}")


def main():
    port = int(_env("WEBHOOK_PORT", "9095"))
    server = http.server.HTTPServer(("0.0.0.0", port), WebhookHandler)
    print(f"sre-webhook listening on :{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()