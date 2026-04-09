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

    # HA: same encrypted token as life-coach, decrypted independently
    # under our own user (see life-coach.nix age.secrets.ha-vacuum-token).
    haUrl = "http://127.0.0.1:8123";
    haTokenFile = config.age.secrets.ha-vacuum-token.path;
  };

  # Let lifecoach's dispatch-robot wrapper write to vacuum-organism's
  # dispatch.org. The vacuum-organism module makes the state dir
  # group-writable; this puts the lifecoach service user in that group.
  users.users.life-coach.extraGroups = [ "vacuum-organism" ];
}
