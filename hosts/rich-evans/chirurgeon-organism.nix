# chirurgeon-organism: host enablement for the Chirurgeon Vahan (#62), the
# 9th bridge officer — the household axis. Built by dissolving lifecoach into
# a bridge officer that is BOTH realtime-editable (org-merge persists * Regimen
# edits in-cycle, no deploy) AND bridge-routed (the medicae-infer shell emits
# the JSON envelope the vox-organism daemon parses).
#
# Phase 2 (this deploy): the Chirurgeon goes live ALONGSIDE an untouched
# lifecoach, taking ONE duty — the day's appointments/schedule (the calendar
# axis). Meds/water/sleep/meals/movement + desk buttons stay the lifecoach's
# until phases 3-4 move them (the seed's phase-2 gate enforces this). lifecoach
# is the silent fallback throughout; nothing of it is touched here.
#
# The module (chirurgeon_organism/nixos/module.nix) is self-contained — it
# resolves its own package from pkgs.system, so this file is CONFIG-ONLY and
# needs NO extraSpecialArgs (same shape as the Confessor/Factotum/Explorator
# host files). `inputs` is available via mkServer's specialArgs (used for the
# org-agent emacs binary + init.el that build-view cold-starts).
#
# Rollback: `services.chirurgeon-organism.enable = false` (one line) + revert
# the routing row / scope stanza / OFFICER_REPOS entry in 40k_bridge + rebuild.
# The lifecoach was never touched, so it is the live fallback. No state lost
# (the Chirurgeon's * Regimen is in its own stateDir, inert after disable).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  org-agent-emacs = inputs.org-agent.packages.${pkgs.system}.emacs;
  org-agent-init = "${inputs.org-agent}/elisp/init.el";
in {
  services.chirurgeon-organism = {
    enable = true;

    # Cloud model tier (via historian's ollama, which proxies to ollama cloud).
    # kimi-k2.7-code:cloud is the sonnet/opus-tier model used by lifecoach +
    # the other officers. medicae-infer sets think:false (load-bearing for
    # kimi/gemma/qwen) + num_predict:4096 (the real output cap on Cloud) in
    # the shell itself. Ollama cloud only — never a local model (esp. while
    # the Lord-Captain games).
    ollamaHost = "http://historian.nebula:11434";
    ollamaModel = "kimi-k2.7-code:cloud";

    # Calendar cadence (phase 2): re-evaluate the day's appointments every
    # 15m. Tighten when the regimen duties move in phases 3-4.
    heartbeatInterval = "15min";

    # Home Assistant — the Auspex (ha-get-state) + compel-spirit. REUSES the
    # existing lifecoach HA token (the vacuum pattern: one .age decrypted for
    # a second user, NO agenix re-encryption — see life-coach.nix for the
    # ha-chirurgeon-token secret wired to the same .age file, owner
    # chirurgeon-organism).
    haUrl = "http://127.0.0.1:8123";
    haTokenFile = config.age.secrets.ha-chirurgeon-token.path;

    # Matrix — the durable bridge-room delivery rung (matrix-page / lib/matrix.py
    # in the chirurgeon package). REUSES the @vox-bridge token (the vacuum pattern
    # again: the same matrix-vox-bridge-token.age decrypted for chirurgeon-organism
    # as matrix-chirurgeon-token, owner chirurgeon-organism 0400 — see the stanza
    # in vox-organism.nix). The room (#chirurgeon:kimb.dev) + homeserver URL default
    # to loopback tuwunel in the module. This is the linchpin of the 2026-07-30
    # outage fix: gives the heartbeat a Matrix egress so med nudges reach the one
    # durable channel instead of dying with the HA/Cast/phone stack.
    matrixTokenFile = config.age.secrets.matrix-chirurgeon-token.path;

    # org-agent regimen view — build-view cold-starts a fresh `emacs --batch`
    # per call (NO daemon, NO socket), sidestepping emacs's 0700-socket-dir
    # rule that locked non-owners out of the old emacsclient path (#82/#83).
    # The chirurgeon-organism user is in the life-coach group (extraGroups,
    # set in the module) so it can traverse /var/lib/life-coach-agent (0750)
    # and READ the 0644 regimen file. lifecoach's daemon stays the WRITER.
    orgAgentEmacs = "${org-agent-emacs}/bin/emacs";
    orgAgentInit = org-agent-init;
    orgAgentFile = "/var/lib/life-coach-agent/agent.org";

    # TTS — speak / lib/tts.py (rung-2 smart-speaker vox). Same Qwen3-TTS
    # server as lifecoach; the voice is the Chirurgeon's own. Device is the
    # bedroom Nest ("Living Room speaker") — the only reliably-castable
    # speaker; the kitchen "Kim's nest hub" is chronically unavailable, and
    # the Captain sleeps in the bedroom so the wake must target it.
    ttsServer = "http://total-eclipse.nebula:8091";
    ttsVoice = "jet2";
    ttsDevice = "Living Room speaker";
  };
}