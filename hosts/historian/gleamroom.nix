# Gleamroom Life Coach Agent
# Drop-in replacement for claude_yapper, using Gleam/OTP instead of Python
#
# SETUP: After deploying, SSH in and run:
#   sudo -u gleamroom -i
#   claude login
# Select "Claude account with subscription" and authenticate.
#
# Also ensure the vision model is available:
#   ollama pull qwen3-vl
{
  config,
  lib,
  pkgs,
  gleamroom,
  ...
}: let
  registry = import ../nebula-registry.nix;
in {
  # Agenix secret for HA token (reusing existing life-coach token)
  age.secrets.ha-life-coach-token = {
    file = ../../secrets/ha-life-coach-token.age;
    owner = "gleamroom";
    mode = "0400";
  };

  # Create dedicated user (regular user so claude login works)
  users.users.gleamroom = {
    isNormalUser = true;
    group = "gleamroom";
    home = "/var/lib/gleamroom";
    createHome = true;
    extraGroups = ["video"];
  };
  users.groups.gleamroom = {};

  services.gleamroom = {
    enable = false;
    package = gleamroom.packages.${pkgs.system}.default;
    port = 8080;
    model = "haiku";
    timezone = "America/New_York";

    homeAssistant.url = "http://${registry.nodes.rich-evans.ip}:8123";

    ollama = {
      host = "http://${registry.nodes.total-eclipse.ip}:11434"; # NVIDIA GPU host
      model = "qwen3-vl:8b-instruct";
    };

    piperModel = "/var/lib/gleamroom/voices/en_US-amy-medium.onnx";
    castDevice = "Living Room speaker";

    # Dual camera setup on rich-evans
    cameras = [
      {
        name = "bed";
        url = "http://${registry.nodes.rich-evans.ip}:8554/cam0";
        description = "Bedroom - monitors bed area, sleep tracking, wake-up";
      }
      {
        name = "desk";
        url = "http://${registry.nodes.rich-evans.ip}:8554/cam1";
        description = "Workspace - monitors desk activity, posture, work sessions";
      }
    ];

    openFirewall = true;

    # Add required tools to PATH
    extraPath = with pkgs; [
      piper-tts
      ffmpeg
      catt
      curl
      jq
      claude-code
    ];
  };

  # Override systemd service for dedicated user and secret loading
  systemd.services.gleamroom = {
    environment = {
      HOME = "/var/lib/gleamroom";
      SHELL = "${pkgs.bash}/bin/bash";
    };
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "gleamroom";
      Group = "gleamroom";
      # Create env file from agenix secret (+ prefix runs as root)
      ExecStartPre = "+${pkgs.writeShellScript "gleamroom-setup-env" ''
        mkdir -p /run/gleamroom
        echo "HA_TOKEN=$(cat ${config.age.secrets.ha-life-coach-token.path})" > /run/gleamroom/env
        chown gleamroom:gleamroom /run/gleamroom/env
        chmod 400 /run/gleamroom/env
      ''}";
      EnvironmentFile = "/run/gleamroom/env";
    };
  };

  # Download Piper voice model on activation
  system.activationScripts.gleamroom-voices = lib.stringAfter ["users"] ''
    mkdir -p /var/lib/gleamroom/voices
    chown gleamroom:gleamroom /var/lib/gleamroom/voices
    VOICE="/var/lib/gleamroom/voices/en_US-amy-medium.onnx"
    if [ ! -f "$VOICE" ]; then
      echo "Downloading Piper voice model..."
      ${pkgs.curl}/bin/curl -sL -o "$VOICE" \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx"
      ${pkgs.curl}/bin/curl -sL -o "$VOICE.json" \
        "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx.json"
      chown gleamroom:gleamroom "$VOICE" "$VOICE.json"
    fi
  '';

  # Add claude-code so gleamroom user can run `claude login`
  environment.systemPackages = [pkgs.claude-code];

  # Open dashboard port on firewall (for LAN access)
  networking.firewall.allowedTCPPorts = [8080];
}
