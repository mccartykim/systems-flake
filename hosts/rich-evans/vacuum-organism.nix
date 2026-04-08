# vacuum-organism: truant-officer sidekick to lifecoach_organism.
#
# Reuses ha-life-coach-token for HA reads (off-duty switch +
# find-me/belay button polling). A dedicated ha-vacuum-token can
# be added later if separation is wanted; see HA_SETUP.md in the
# vacuum_organism repo.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.vacuum-organism = {
    enable = true;
    stateDir = "/var/lib/vacuum-organism";
    heartbeatInterval = "30min";

    # Robot connectivity (defaults match the live install).
    vacuumHost = "10.100.0.60";

    # Qwen3-TTS for the biden-legs voice.
    qwenTtsServer = "http://total-eclipse.nebula:8091";
    qwenTtsVoice = "biden-legs";

    # HA: reuse the life-coach token for the polling loop.
    haUrl = "http://127.0.0.1:8123";
    haTokenFile = config.age.secrets.ha-life-coach-token.path;
  };
}
