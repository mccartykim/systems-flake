# SRE Agent NixOS Module
# Phase 0: observability foundation — stub webhook receiver that logs
# Alertmanager alerts and posts summaries to Discord. No LLM, no GitHub
# API calls yet (those arrive in Phase 1/2).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.sreAgent;

  webhookScript = pkgs.writeScript "sre-webhook" ''
    #!${pkgs.python3}/bin/python3
    import http.server, json, os, subprocess, sys, urllib.request
    from datetime import datetime, timezone

    STATE_DIR = os.environ["STATE_DIR"]
    TOKEN_FILE = os.environ["DISCORD_TOKEN_FILE"]
    CHANNEL_ID = os.environ["DISCORD_CHANNEL_ID"]
    ALERTS_LOG = os.path.join(STATE_DIR, "alerts.jsonl")

    def post_discord(msg):
        if not CHANNEL_ID or CHANNEL_ID == "TODO":
            print(f"discord: no channel id configured, skipping: {msg}", file=sys.stderr)
            return
        try:
            with open(TOKEN_FILE) as f:
                token = f.read().strip()
            if not token or token.startswith("PLACEHOLDER"):
                print("discord: token is placeholder, skipping", file=sys.stderr)
                return
            data = json.dumps({"content": msg[:2000]}).encode()
            req = urllib.request.Request(
                f"https://discord.com/api/v10/channels/{CHANNEL_ID}/messages",
                data=data,
                headers={"Authorization": f"Bot {token}", "Content-Type": "application/json"},
            )
            urllib.request.urlopen(req, timeout=10)
        except Exception as e:
            print(f"discord post failed: {e}", file=sys.stderr)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            try:
                payload = json.loads(body)
            except json.JSONDecodeError:
                self.send_response(400)
                self.end_headers()
                return

            # Append to log
            with open(ALERTS_LOG, "a") as f:
                f.write(json.dumps({"ts": datetime.now(timezone.utc).isoformat(), **payload}) + "\n")

            # Format Discord message
            status = payload.get("status", "unknown")
            alerts = payload.get("alerts", [])
            lines = [f"[{status.upper()}]"]
            for a in alerts:
                labels = a.get("labels", {})
                annotations = a.get("annotations", {})
                name = labels.get("alertname", "unknown")
                instance = labels.get("instance", "?")
                summary = annotations.get("summary", annotations.get("description", ""))
                lines.append(f"**{name}** ({instance}): {summary}")
            msg = "\n".join(lines)
            print(msg)
            post_discord(msg)

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')

        def log_message(self, fmt, *args):
            print(f"webhook: {fmt % args}")

    server = http.server.HTTPServer(("0.0.0.0", ${toString cfg.webhookPort}), Handler)
    print(f"sre-webhook listening on :${toString cfg.webhookPort}")
    server.serve_forever()
  '';
in {
  options.kimb.sreAgent = {
    enable = mkEnableOption "SRE agent (home observability)";

    user = mkOption {
      type = types.str;
      default = "sre-agent";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/sre-agent";
    };

    discordTokenFile = mkOption {
      type = types.path;
      description = "Agenix path to Discord bot token";
    };

    githubTokenFile = mkOption {
      type = types.path;
      description = "Agenix path to GitHub PAT (Issues: write on homelab-incidents)";
    };

    githubRepo = mkOption {
      type = types.str;
      default = "mccartykim/homelab-incidents";
    };

    alertChannelId = mkOption {
      type = types.str;
      default = "TODO";
      description = "Discord channel ID for alert notifications";
    };

    webhookPort = mkOption {
      type = types.port;
      default = 9095;
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = cfg.stateDir;
    };
    users.groups.${cfg.user} = {};

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 ${cfg.user} ${cfg.user} -"
    ];

    systemd.services.sre-agent-webhook = {
      description = "SRE Agent Alertmanager Webhook Receiver";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        ExecStart = webhookScript;
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "5s";

        Environment = [
          "STATE_DIR=${cfg.stateDir}"
          "DISCORD_TOKEN_FILE=${cfg.discordTokenFile}"
          "DISCORD_CHANNEL_ID=${cfg.alertChannelId}"
        ];

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.stateDir];
        ReadOnlyPaths = [cfg.discordTokenFile cfg.githubTokenFile];
      };
    };
  };
}
