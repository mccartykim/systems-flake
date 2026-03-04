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

    orgFile = "/home/life-coach/agent.org";
    interval = 300;  # 5 minutes

    # LLM for reasoning (uses claude CLI by default)
    # provider = "anthropic";
    # model = "claude-haiku-4-5-20251001";

    # Home Assistant (same host)
    haUrl = "http://127.0.0.1:8123";
    haTokenFile = config.age.secrets.ha-life-coach-token.path;

    # Cameras (webcam server on same host)
    cameraBedUrl = "http://127.0.0.1:8554/cam0";
    cameraDeskUrl = "http://127.0.0.1:8554/cam1";

    # VLM on historian
    vlmHost = "http://historian.nebula:11434";
    vlmModel = "qwen3-vl:30b-instruct";
  };

  # Set HOME so claude CLI can find credentials
  systemd.services.org-life-coach.environment = {
    HOME = "/var/lib/life-coach-agent";
    SHELL = "${pkgs.bash}/bin/bash";
  };

  # Add claude-code so life-coach user can run `claude login`
  environment.systemPackages = [ pkgs.claude-code ];

  # Open port for TTS audio serving to Chromecast
  # (already opened by the module, but explicit here for documentation)
}
