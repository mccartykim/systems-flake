"""SRE Agent entry point.

Usage:
    python3 -m sre_agent webhook   — Start Alertmanager webhook receiver
    python3 -m sre_agent discord   — Start Discord bot (Phase 1.5)
"""
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 -m sre_agent [webhook|discord]", file=sys.stderr)
        sys.exit(1)

    mode = sys.argv[1]
    if mode == "webhook":
        from webhook import main as webhook_main
        webhook_main()
    elif mode == "discord":
        from discord_bot import main as discord_main
        discord_main()
    else:
        print(f"Unknown mode: {mode}. Use 'webhook' or 'discord'.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()