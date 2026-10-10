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
  # DISABLED 2026-10-10 — moving soon (see hosts/rich-evans/lifecoach-organism.nix).
  # The vacuum user/group + its two secret stanzas below are REMOVED with the
  # disable: the module's mkIf cfg.enable no longer creates the user, so the
  # agenix secrets owned by "vacuum-organism" and the life-coach extraGroups
  # grant would break activation. Re-enabling means restoring this block from
  # the pre-disable commit (see docs/lifecoach-handoff.md).
  services.vacuum-organism = {
    enable = false;
    stateDir = "/var/lib/vacuum-organism";
    heartbeatInterval = "30min";

    # Robot connectivity (defaults match the live install).
    vacuumHost = "10.100.0.60";

    # Qwen3-TTS for the biden-legs voice.
    qwenTtsServer = "http://historian.nebula:8091"; # a3j.9.1: was total-eclipse
    qwenTtsVoice = "biden-legs";

    # HA: same encrypted token as life-coach, decrypted independently
    # under our own user. Null'd with the 2026-10-10 disable (the
    # ha-vacuum-token secret entry is removed from life-coach.nix;
    # restore both together on re-enable).
    haUrl = "http://10.100.0.10:8123";
    haTokenFile = null;

    # Discord bot sidecar. Token is decrypted per-host via agenix;
    # the allowlist is Kimb (ikea_femme) + Lily (parsimony). An empty
    # the allowlist would be fail-closed (refuse all) — the vacuum bot
    # deliberately diverges from life-coach's empty-means-allow-all
    # default because this bot controls motion.
    # discordBotTokenFile null'd with the 2026-10-10 disable (its secret
    # stanza was removed above; restore together on re-enable).
    discordBotTokenFile = null;
    discordAllowedUsers = "366455267673636866,100735298694021120";
  };

  # a3j.9-model: the module's cycleEnv hardcodes OLLAMA_MODEL=kimi; force
  # deepseek on every vacuum service (heartbeat/scheduler run the LLM cycles;
  # watchdog/bot get it too for consistency). Inert while enable = false —
  # mkIf-gated with the 2026-10-10 disable so these don't linger as bare
  # Environment-only unit files for services the module no longer creates.
  systemd.services = lib.mkIf config.services.vacuum-organism.enable
    (lib.genAttrs ["vacuum-heartbeat" "vacuum-scheduler" "vacuum-watchdog" "vacuum-discord-bot"] (_: {
      environment.OLLAMA_MODEL = lib.mkForce "deepseek-v4.1-flash:cloud";
      environment.ORG_AGENT_LLM_MODEL = lib.mkForce "deepseek-v4.1-flash:cloud";
    }));

  # Discord bot token for the vacuum-organism sidecar — REMOVED with the
  # 2026-10-10 disable (secrets owned by the vanished "vacuum-organism" user
  # break agenix activation). Restore from the pre-disable commit on re-enable.
  # The .age file itself stays in secrets/ (rekeyed to fleet-core in
  # secrets/secrets.nix), so nothing is lost.

  # life-coach's membership in the vacuum-organism group — REMOVED with the
  # 2026-10-10 disable (the group no longer exists). Restore on re-enable.
}
