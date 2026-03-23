# org-life-coach: Autonomous life coach agent
#
# Replaces claude_yapper's life-coach-agent service.
# Uses org-mode + emacs daemon + unified vision+reasoning model.
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

    # Single omnimodal model — vision + text reasoning in one call
    provider = "ollama";
    model = "qwen3.5:27b";
    ollamaHost = "http://historian.nebula:11434";

    # Home Assistant (same host)
    haUrl = "http://127.0.0.1:8123";
    haTokenFile = config.age.secrets.ha-life-coach-token.path;

    # TTS voice
    ttsVoice = "biden-legs";

    # Cameras (webcam server on same host)
    # cam0 = /dev/video0 = desk, cam1 = /dev/video2 = bed
    cameraBedUrl = "http://127.0.0.1:8554/cam1";
    cameraDeskUrl = "http://127.0.0.1:8554/cam0";

    # Matrix chatbot (Tuwunel on same host)
    matrixHomeserver = "http://127.0.0.1:6167";
    matrixBotUser = "@lifecoach:kimb.dev";
    matrixBotTokenFile = config.age.secrets.matrix-life-coach-token.path;

    # Discord bot
    discordBotTokenFile = config.age.secrets.discord-life-coach-token.path;
  };

  # Extra environment for org-life-coach service
  systemd.services.org-life-coach.environment = {
    # Kasa smart plug IPs
    KASA_BEDROOM_LAMP = "192.168.69.152";
    # KASA_DESK_LAMP = "";  # TODO: find desk lamp IP (not currently on network)

    VLM_HOST = "http://historian.nebula:11434";
    OLLAMA_TIMEOUT = "600";
    OLLAMA_NUM_CTX = "8192";
  };

  # Open port for TTS audio serving to Chromecast
  # (already opened by the module, but explicit here for documentation)
}
