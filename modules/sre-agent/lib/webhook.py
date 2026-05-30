"""SRE Agent Webhook Receiver — Alertmanager webhook HTTP server.

Receives alerts from Alertmanager, optionally runs LLM triage, posts to
Discord, and creates GitHub issues when appropriate.
"""
import http.server
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

# Add lib directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# --- Discord rate limiter state ---
_last_discord_post = 0
_DISCORD_MIN_INTERVAL = 1.0  # seconds between posts

# Per-alertname dedupe: drop repeated fire/triage posts for the same alertname
# within this window. alertmanager's repeat_interval is 4h, so anything shorter
# is a burst from the agent itself (retries, triage cascades) and worth squashing.
_alertname_last_post = {}
_ALERTNAME_DEDUPE_SECONDS = 600  # 10 minutes

# Alerts that should never be triaged via LLM — including alerts about the LLM
# itself (recursive loop: agent can't reach ollama → triage call to ollama → ...)
SKIP_TRIAGE_ALERTS = {"OllamaUnreachable", "NodeExporterDown"}


def _env(key, default=""):
    return os.environ.get(key, default)


def post_discord(msg):
    """Post a message to the configured Discord channel.

    Implements rate limiting: enforces a minimum interval between posts and
    retries on HTTP 429 (Discord rate limit) using the retry_after hint.
    """
    global _last_discord_post
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
        # Rate limit: ensure minimum interval between posts
        now = time.monotonic()
        wait = _DISCORD_MIN_INTERVAL - (now - _last_discord_post)
        if wait > 0:
            time.sleep(wait)
        data = json.dumps({"content": msg[:2000]}).encode()
        req = urllib.request.Request(
            f"https://discord.com/api/v10/channels/{channel_id}/messages",
            data=data,
            headers={"Authorization": f"Bot {token}", "Content-Type": "application/json", "User-Agent": "sre-agent/1.0"},
        )
        try:
            urllib.request.urlopen(req, timeout=10)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                # Discord rate limit — extract retry_after and wait
                try:
                    body = json.loads(e.read().decode())
                    retry_after = body.get("retry_after", 5)
                except (json.JSONDecodeError, AttributeError):
                    retry_after = 5
                print(f"discord: rate limited, retrying after {retry_after}s", file=sys.stderr)
                time.sleep(retry_after)
                urllib.request.urlopen(req, timeout=10)
            else:
                raise
        _last_discord_post = time.monotonic()
    except Exception as e:
        print(f"discord post failed: {e}", file=sys.stderr)


def post_discord_for_alert(alertname, msg):
    """Post to Discord, dropping bursts of the same alertname.

    Used for fire/triage messages where alertmanager re-fires + agent retries
    can flood the channel. One-shot messages (resolved, issue created,
    silenced) should call post_discord() directly.
    """
    now = time.monotonic()
    last = _alertname_last_post.get(alertname, 0)
    if now - last < _ALERTNAME_DEDUPE_SECONDS:
        print(f"discord: deduped {alertname} (last post {int(now - last)}s ago)", file=sys.stderr)
        return
    _alertname_last_post[alertname] = now
    post_discord(msg)


def format_alert(payload):
    """Format an Alertmanager webhook payload into a Discord-ready message.

    Deduplicates alerts by (alertname, instance) so repeated firings of the
    same alert within a group don't produce duplicate lines.
    """
    status = payload.get("status", "unknown")
    alerts = payload.get("alerts", [])
    seen = set()
    lines = [f"[{status.upper()}]"]
    for a in alerts:
        labels = a.get("labels", {})
        key = (labels.get("alertname", "unknown"), labels.get("instance", "?"))
        if key in seen:
            continue
        seen.add(key)
        annotations = a.get("annotations", {})
        name = key[0]
        instance = key[1]
        summary = annotations.get("summary", annotations.get("description", ""))
        lines.append(f"**{name}** ({instance}): {summary}")
    return "\n".join(lines)


def format_resolved(payload):
    """Format a resolved alert for Discord."""
    alerts = payload.get("alerts", [])
    lines = ["[RESOLVED]"]
    for a in alerts:
        labels = a.get("labels", {})
        name = labels.get("alertname", "unknown")
        instance = labels.get("instance", "?")
        lines.append(f"**{name}** ({instance}) resolved")
    return "\n".join(lines)


def run_triage(alert):
    """Run LLM triage on a single alert dict. Returns TriageResult or None."""
    enable_llm = _env("ENABLE_LLM_TRIAGE", "false").lower() in ("true", "1", "yes")
    if not enable_llm:
        return None

    labels = alert.get("labels", {})
    alertname = labels.get("alertname", "unknown")
    if alertname in SKIP_TRIAGE_ALERTS:
        print(f"triage: skipping {alertname} (in SKIP_TRIAGE_ALERTS)", file=sys.stderr)
        return None

    from llm_client import triage
    annotations = alert.get("annotations", {})
    return triage(
        alertname=alertname,
        severity=labels.get("severity", "unknown"),
        instance=labels.get("instance", "?"),
        summary=annotations.get("summary", annotations.get("description", "")),
    )


def maybe_file_issue(alert, triage_result):
    """Create a GitHub issue if triage recommends it.

    Returns (issue_url, was_created) — was_created is True if a new issue was
    created, False if an existing issue was found. Returns (None, False) on failure.
    """
    if triage_result is None or not triage_result.file_issue:
        return (None, False)

    from github_client import create_issue

    labels = alert.get("labels", {})
    title = triage_result.issue_title or f"[SRE] {labels.get('alertname', 'unknown')}"

    annotations = alert.get("annotations", {})
    body_parts = [
        f"## Alert: {labels.get('alertname', 'unknown')}",
        f"**Severity:** {triage_result.severity}",
        f"**Instance:** {labels.get('instance', '?')}",
        f"**Summary:** {annotations.get('summary', '')}",
        "",
        "### LLM Triage",
        f"- **Cause:** {triage_result.cause}",
        f"- **Action:** {triage_result.action}",
    ]

    result = create_issue(
        title=title,
        body="\n".join(body_parts),
        alertname=labels.get("alertname", "unknown"),
        instance=labels.get("instance", "?"),
    )
    return (result[0], result[1]) if result[0] else (None, False)


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

        # Format for Discord — dedupe per alertname (alertmanager groups by alertname+instance)
        msg = format_alert(payload)
        print(msg)
        alerts = payload.get("alerts", [])
        primary_alertname = alerts[0].get("labels", {}).get("alertname", "unknown") if alerts else "unknown"
        post_discord_for_alert(primary_alertname, msg)

        # Handle resolved alerts — close GitHub issues
        if payload.get("status") == "resolved":
            for alert in payload.get("alerts", []):
                labels = alert.get("labels", {})
                alertname = labels.get("alertname", "unknown")
                instance = labels.get("instance", "")
                from github_client import close_issue
                closed_url = close_issue(alertname, instance)
                if closed_url:
                    ts = datetime.now(timezone.utc).strftime("%H:%M UTC")
                    post_discord(f"[{ts}] **Issue closed:** {closed_url}")
            # Also post resolved message
            resolved_msg = format_resolved(payload)
            post_discord(resolved_msg)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
            return

        # Optional LLM triage
        for alert in payload.get("alerts", []):
            result = run_triage(alert)
            if result:
                ts = datetime.now(timezone.utc).strftime("%H:%M UTC")
                triage_msg = (
                    f"[{ts}] **Triage:** {result.severity} | Cause: {result.cause} | Action: {result.action}"
                )
                if result.file_issue:
                    triage_msg += f" | Filing issue: {result.issue_title or 'yes'}"
                alertname = alert.get("labels", {}).get("alertname", "unknown")
                post_discord_for_alert(f"{alertname}:triage", triage_msg)

                # Maybe create a GitHub issue
                issue_url, was_created = maybe_file_issue(alert, result)
                if issue_url:
                    ts = datetime.now(timezone.utc).strftime("%H:%M UTC")
                    if was_created:
                        post_discord(f"[{ts}] Issue created: {issue_url}")
                    else:
                        post_discord(f"[{ts}] Issue already tracked: {issue_url}")

                # Maybe silence noise/info/warning alerts
                if result.silence_hours > 0 and result.severity in ("noise", "info", "warning"):
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
