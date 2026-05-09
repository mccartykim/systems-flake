# SRE Agent NixOS Module
# Phase 0→1: webhook receiver + LLM triage + redaction + GitHub issues
# Phase 1.5: Discord bot (optional)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.sreAgent;

  # Assemble the sre_agent Python package as a directory in the Nix store.
  # No setuptools/pyproject — pure stdlib, deployed via writeTextDir + PYTHONPATH.
  sreAgentLib = pkgs.runCommand "sre-agent-lib" {} ''
    mkdir -p $out
    cp ${pkgs.writeText "sre-agent-__main__.py" (builtins.readFile ./sre-agent/lib/__main__.py)} $out/__main__.py
    cp ${pkgs.writeText "sre-agent-webhook.py" (builtins.readFile ./sre-agent/lib/webhook.py)} $out/webhook.py
    cp ${pkgs.writeText "sre-agent-redaction.py" (builtins.readFile ./sre-agent/lib/redaction.py)} $out/redaction.py
    cp ${pkgs.writeText "sre-agent-llm_client.py" (builtins.readFile ./sre-agent/lib/llm_client.py)} $out/llm_client.py
    cp ${pkgs.writeText "sre-agent-github_client.py" (builtins.readFile ./sre-agent/lib/github_client.py)} $out/github_client.py
    cp ${pkgs.writeText "sre-agent-discord_bot.py" (builtins.readFile ./sre-agent/lib/discord_bot.py)} $out/discord_bot.py
    cp ${pkgs.writeText "sre-agent-silence_client.py" (builtins.readFile ./sre-agent/lib/silence_client.py)} $out/silence_client.py
  '';

  # Python with discord.py for the Discord bot service
  discordPython = pkgs.python3.withPackages (p: [p.discordpy]);
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

    ollamaHost = mkOption {
      type = types.str;
      default = "http://total-eclipse.nebula:11434";
      description = "Primary Ollama endpoint (local, supports format:json)";
    };

    ollamaModel = mkOption {
      type = types.str;
      default = "qwen3:14b";
      description = "Primary Ollama model for triage";
    };

    ollamaCloudHost = mkOption {
      type = types.str;
      default = "https://ollama.com";
      description = "Fallback Ollama Cloud endpoint";
    };

    ollamaCloudModel = mkOption {
      type = types.str;
      default = "glm-5";
      description = "Fallback Ollama Cloud model (free-form only)";
    };

    ollamaCloudKeyFile = mkOption {
      type = types.path;
      description = "Agenix path to Ollama Cloud API key";
    };

    enableDiscordBot = mkOption {
      type = types.bool;
      default = false;
      description = "Enable the Discord slash-command bot (/status, /investigate)";
    };

    enableLlmTriage = mkOption {
      type = types.bool;
      default = false;
      description = "Enable LLM triage via Ollama (opt-in: alert text will be sent to LLM)";
    };

    prometheusUrl = mkOption {
      type = types.str;
      default = "http://10.100.0.50:9090";
      description = "Prometheus URL for alert queries";
    };

    silenceUrl = mkOption {
      type = types.str;
      default = "http://10.100.0.1:9093/api/v2/silences";
      description = "Alertmanager silences API URL";
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

      path = with pkgs; [curl jq];

      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${sreAgentLib}/__main__.py webhook";
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "5s";

        Environment = [
          "PYTHONPATH=${sreAgentLib}"
          "STATE_DIR=${cfg.stateDir}"
          "DISCORD_TOKEN_FILE=${cfg.discordTokenFile}"
          "DISCORD_CHANNEL_ID=${cfg.alertChannelId}"
          "WEBHOOK_PORT=${toString cfg.webhookPort}"
          "OLLAMA_HOST=${cfg.ollamaHost}"
          "OLLAMA_MODEL=${cfg.ollamaModel}"
          "OLLAMA_CLOUD_HOST=${cfg.ollamaCloudHost}"
          "OLLAMA_CLOUD_MODEL=${cfg.ollamaCloudModel}"
          "OLLAMA_CLOUD_KEY_FILE=${cfg.ollamaCloudKeyFile}"
          "GITHUB_TOKEN_FILE=${cfg.githubTokenFile}"
          "GITHUB_REPO=${cfg.githubRepo}"
          "ENABLE_LLM_TRIAGE=${if cfg.enableLlmTriage then "true" else "false"}"
          "PROMETHEUS_URL=${cfg.prometheusUrl}"
          "SILENCE_URL=${cfg.silenceUrl}"
        ];

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.stateDir];
        ReadOnlyPaths = [cfg.discordTokenFile cfg.githubTokenFile cfg.ollamaCloudKeyFile];
      };
    };

    systemd.services.sre-agent-discord = mkIf cfg.enableDiscordBot {
      description = "SRE Agent Discord Bot";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      path = with pkgs; [curl jq];

      serviceConfig = {
        ExecStart = "${pkgs.writeShellScript "sre-agent-discord" ''
          export PYTHONPATH="${sreAgentLib}:$PYTHONPATH"
          exec ${discordPython}/bin/python3 ${sreAgentLib}/__main__.py discord
        ''}";
        User = cfg.user;
        Group = cfg.user;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "5s";

        Environment = [
          "STATE_DIR=${cfg.stateDir}"
          "DISCORD_TOKEN_FILE=${cfg.discordTokenFile}"
          "DISCORD_CHANNEL_ID=${cfg.alertChannelId}"
          "OLLAMA_HOST=${cfg.ollamaHost}"
          "OLLAMA_MODEL=${cfg.ollamaModel}"
          "OLLAMA_CLOUD_HOST=${cfg.ollamaCloudHost}"
          "OLLAMA_CLOUD_MODEL=${cfg.ollamaCloudModel}"
          "OLLAMA_CLOUD_KEY_FILE=${cfg.ollamaCloudKeyFile}"
          "GITHUB_TOKEN_FILE=${cfg.githubTokenFile}"
          "GITHUB_REPO=${cfg.githubRepo}"
          "ENABLE_LLM_TRIAGE=${if cfg.enableLlmTriage then "true" else "false"}"
          "PROMETHEUS_URL=${cfg.prometheusUrl}"
          "SILENCE_URL=${cfg.silenceUrl}"
        ];

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.stateDir];
        ReadOnlyPaths = [cfg.discordTokenFile cfg.githubTokenFile cfg.ollamaCloudKeyFile];
      };
    };
  };
}