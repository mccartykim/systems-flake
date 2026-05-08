"""SRE Agent Discord Bot — slash commands for alert status and investigation.

Phase 1.5: /status command queries Prometheus and posts a rich embed.
Phase 2: /investigate command triggers deep investigation.

Uses discord.py + app_commands.CommandTree (not py-cord).
"""
import json
import os
import sys
import urllib.request

# Ensure lib directory is on path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from redaction import redact

# discord.py is a runtime dependency — only needed when running as bot
try:
    import discord
    from discord.ext import app_commands
except ImportError:
    discord = None
    app_commands = None


def _env(key, default=""):
    return os.environ.get(key, default)


def fetch_alerts(prometheus_url: str) -> list:
    """Fetch active alerts from Prometheus /api/v1/alerts."""
    url = f"{prometheus_url}/api/v1/alerts"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        resp = urllib.request.urlopen(req, timeout=10)
        data = json.loads(resp.read().decode())
        if data.get("status") == "success":
            return data.get("data", {}).get("alerts", [])
        return []
    except Exception:
        return []


def format_alert_embed(alerts: list) -> dict:
    """Format Prometheus alerts into a Discord embed dict.

    Redacts PII before including in the embed.
    """
    if not alerts:
        return {
            "title": "SRE Alerts",
            "description": "No active alerts — all systems nominal.",
            "color": 0x00FF00,  # green
            "fields": [],
        }

    fields = []
    max_fields = 24 if len(alerts) > 25 else 25  # Reserve 1 slot for overflow message
    for alert in alerts[:max_fields]:
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})
        state = alert.get("state", "unknown")
        name = labels.get("alertname", "unknown")
        severity = labels.get("severity", "unknown")
        instance = redact(labels.get("instance", "?"), context="discord alert instance")
        summary = redact(annotations.get("summary", annotations.get("description", "")), context="discord alert summary")

        emoji = {"firing": "🔴", "pending": "🟡", "inactive": "⚪"}.get(state, "❓")
        field_value = f"{emoji} **{severity}** | {instance}\n{summary}"
        fields.append({
            "name": name,
            "value": field_value[:1024],  # Discord field value limit
            "inline": False,
        })

    if len(alerts) > 25:
        fields.append({
            "name": "...",
            "value": f"and {len(alerts) - 25} more alerts",
            "inline": False,
        })

    return {
        "title": f"SRE Alerts ({len(alerts)} active)",
        "description": None,
        "color": 0xFF0000 if any(a.get("state") == "firing" for a in alerts) else 0xFFFF00,
        "fields": fields,
    }


async def handle_status(interaction):
    """/status command handler — queries Prometheus and responds with alert embed."""
    if discord is None:
        await interaction.response.send_message("discord.py not available", ephemeral=True)
        return

    prometheus_url = _env("PROMETHEUS_URL", "http://10.100.0.50:9090")
    alerts = fetch_alerts(prometheus_url)
    embed_dict = format_alert_embed(alerts)

    embed = discord.Embed(
        title=embed_dict["title"],
        description=embed_dict.get("description"),
        color=embed_dict["color"],
    )
    for field in embed_dict.get("fields", []):
        embed.add_field(name=field["name"], value=field["value"], inline=field.get("inline", False))

    await interaction.response.send_message(embed=embed, ephemeral=True)


def main():
    """Start the Discord bot."""
    if discord is None:
        print("discord.py is not installed. Install python3Packages.discordpy.", file=sys.stderr)
        sys.exit(1)

    token_file = _env("DISCORD_TOKEN_FILE")
    if not token_file or not os.path.exists(token_file):
        print("DISCORD_TOKEN_FILE not set or file not found", file=sys.stderr)
        sys.exit(1)

    with open(token_file) as f:
        token = f.read().strip()

    if not token or token.startswith("PLACEHOLDER"):
        print("Discord token is placeholder or empty", file=sys.stderr)
        sys.exit(1)

    intents = discord.Intents.default()
    client = discord.Client(intents=intents)
    tree = app_commands.CommandTree(client)

    @tree.command(name="status", description="Show current SRE alerts from Prometheus")
    async def status_command(interaction: discord.Interaction):
        await handle_status(interaction)

    @client.event
    async def on_ready():
        print(f"Discord bot logged in as {client.user}")
        try:
            synced = await tree.sync()
            print(f"Synced {len(synced)} command(s)")
        except Exception as e:
            print(f"Command sync failed: {e}", file=sys.stderr)

    client.run(token)


if __name__ == "__main__":
    main()