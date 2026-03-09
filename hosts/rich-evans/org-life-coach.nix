# org-life-coach: Autonomous life coach agent
#
# Replaces claude_yapper's life-coach-agent service.
# Uses org-mode + emacs daemon + LLM reasoning + VLM cameras.
#
# HA TOKEN: Defined in life-coach.nix (shared agenix secret)
{
  config,
  lib,
  pkgs,
  ...
}: {
  # NOTE: org_life_coach.nixosModules.default is imported at the flake level
  # NOTE: age.secrets.ha-life-coach-token is defined in life-coach.nix

  services.org-life-coach = {
    enable = true;
    user = "life-coach";
    stateDir = "/var/lib/life-coach-agent";

    orgFile = "/var/lib/life-coach-agent/agent.org";
    interval = 300;  # 5 minutes

    # LLM for reasoning
    provider = "ollama";
    model = "qwen3:8b";

    # Home Assistant (same host)
    haUrl = "http://127.0.0.1:8123";
    haTokenFile = config.age.secrets.ha-life-coach-token.path;

    # Cameras (webcam server on same host)
    # cam0 = /dev/video0 = desk, cam1 = /dev/video2 = bed
    cameraBedUrl = "http://127.0.0.1:8554/cam1";
    cameraDeskUrl = "http://127.0.0.1:8554/cam0";

    # VLM on historian
    vlmHost = "http://historian.nebula:11434";
    vlmModel = "qwen3-vl:30b-instruct";
  };

  # Set HOME so claude CLI can find credentials, plus Kasa plug IPs
  systemd.services.org-life-coach.environment = {
    HOME = "/var/lib/life-coach-agent";
    SHELL = "${pkgs.bash}/bin/bash";
    OLLAMA_HOST = "http://total-eclipse.nebula:11434";
    KASA_BEDROOM_LAMP = "192.168.69.152";
    # KASA_DESK_LAMP = "";  # TODO: find desk lamp IP (not currently on network)
  };

  # Add claude-code so life-coach user can run `claude login`
  environment.systemPackages = [ pkgs.claude-code ];

  # Open port for TTS audio serving to Chromecast
  # (already opened by the module, but explicit here for documentation)
}
