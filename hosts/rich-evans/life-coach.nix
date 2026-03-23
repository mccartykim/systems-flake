# Life Coach Agent (claude_yapper) — DISABLED
# Replaced by org-life-coach. Keeping this file for the dashboard and
# user/group config (shared with org-life-coach) until full migration.
#
# To remove entirely: delete this file and its import in nixos-configurations.nix
{
  config,
  lib,
  pkgs,
  claude_yapper,
  ...
}: {
  # Agenix secret for HA token (shared with org-life-coach)
  age.secrets.ha-life-coach-token = {
    file = ../../secrets/ha-life-coach-token.age;
    owner = "life-coach";
    mode = "0400";
  };

  # Matrix access token for life-coach chatbot
  age.secrets.matrix-life-coach-token = {
    file = ../../secrets/matrix-life-coach-token.age;
    owner = "life-coach";
    mode = "0400";
  };

  # User and group are now created by org-life-coach module.
  # Keep these here as lib.mkDefault so they don't conflict.

  # Make state directory accessible to life-coach group (for HA interrupt signals)
  systemd.tmpfiles.rules = [
    "z /var/lib/life-coach-agent 0750 life-coach life-coach -"
    "z /var/lib/life-coach-agent/state.db 0660 life-coach life-coach -"
    "z /var/lib/life-coach-agent/state.db-wal 0660 life-coach life-coach -"
    "z /var/lib/life-coach-agent/state.db-shm 0660 life-coach life-coach -"
  ];

  # Old claude_yapper service — DISABLED
  services.life-coach-agent.enable = false;

  # Open port for TTS audio serving to Chromecast devices
  networking.firewall.allowedTCPPorts = [8555];
}
