# lifecoach-organism: full cutover from org-life-coach.
#
# This file does two things:
#
# 1. Turns on lifecoach-organism with the full feature set
#    (button monitor, discord bot, cameras, dashboard).
#
# 2. Disables the old org-life-coach python daemon, discord
#    bots, and dashboard — while keeping the org-agent emacs daemon
#    running so the new agent can still call emacsclient for the
#    task view and org-task write verbs.
#
# Rollback: set enable = false here and re-enable the old services
# in hosts/rich-evans/org-life-coach.nix. The old daemon's state
# dir (/var/lib/life-coach-agent) is untouched so nothing is lost.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  org-agent-emacs = inputs.org-agent.packages.${pkgs.system}.emacs;
  # Per-service overrides for all lifecoach-organism units
  lifecoach-services = ["lifecoach-heartbeat" "lifecoach-scheduler" "lifecoach-watchdog"
    "lifecoach-discord-bot" "lifecoach-button-monitor" "lifecoach-dashboard"];
in {
  services.lifecoach-organism = {
    enable = true;
    user = "life-coach";
    stateDir = "/var/lib/lifecoach-organism";

    # Heartbeat every 30m. Safety net for when the agent fails to
    # set a close LOOP_AT — which happens reliably when Haiku decides
    # "all tools are ineffective" and parks the next wakeup hours out.
    # At ~$0.04/cycle this costs ~$1.92/day total and guarantees the
    # agent re-evaluates at least twice an hour.
    heartbeatInterval = "30m";

    # dispatch-robot always files real entries to vacuum_organism's
    # dispatch.org when reached. Whether the agent reaches it at all is
    # gated upstream in lifecoach-mechanical.execute_actions.

    # Home Assistant — reuse the existing agenix secret
    haUrl = "http://127.0.0.1:8123";
    haTokenFile = config.age.secrets.ha-life-coach-token.path;

    # Emacs daemon from the old module's socket path. The old
    # org-life-coach module still provides the running org-agent
    # emacs daemon; we just disable its python loop below.
    orgAgentSocket = "/var/lib/life-coach-agent/emacs/org-agent";
    orgAgentEmacsclient = "${org-agent-emacs}/bin/emacsclient";

    # TTS
    ttsServer = "http://total-eclipse.nebula:8091";
    ttsVoice = "caine";
    ttsDevice = "Kim's nest hub";

    # Full cutover: everything on.
    enableButtonMonitor = true;

    discordBotTokenFile = config.age.secrets.discord-life-coach-token.path;
    # discordAllowedUsers left empty = allow all

    # Cameras — same URLs the old daemon was using.
    cameraBedUrl = "http://127.0.0.1:8554/cam0";
    cameraDeskUrl = "http://127.0.0.1:8554/cam1";

    # Dashboard runs on 8586 (the old org-life-coach dashboard on
    # 8585 is mkForce-disabled below). No public reverse-proxy
    # entry exists for it — access is LAN/Nebula only.
    #
    # host = "0.0.0.0": the upstream module defaults to "127.0.0.1"
    # (loopback-only, since the dashboard has no auth and serves
    # agent.org). Override here to preserve mesh access from
    # phone/laptop — the trust boundary is the nebula firewall
    # (port 8586 rule in configuration.nix:144-148), not in-app auth.
    # If you ever want ssh-tunnel-only access, drop this line.
    dashboard = {
      enable = true;
      host = "0.0.0.0";
      port = 8586;
      openFirewall = true;
    };

    # Health watchdog: 5-min timer, alerts via TTS + Discord DM when
    # the agent is broken and can't self-recover. Quiet hours
    # 23:00–08:00 local — see modules/lifecoach-organism.nix for the
    # cadence + dispatch logic.
    watchdog = {
      enable = true;
      # DM channel between the lifecoach bot and Kimb (recipient_id
      # 366455267673636866 — same user org_crm's Secretary bot DMs).
      # Created once via POST /users/@me/channels with the lifecoach bot
      # token; the id is stable. Speak/TTS is the loud channel, gated
      # by quiet hours; this DM is the silent always-fires channel.
      alertChannelId = "1489092456048754719";
    };

    # DISABLED: warmup is pointless with cloud models — they're always
    # warm on the provider side. (Previously kept a local iGPU model
    # resident; that path is retired now that every role uses cloud.)
    ollamaWarmup = {
      enable = false;
      model = "kimi-k2.7-code:cloud";
      interval = "25min";
      keepAlive = "30m";
    };

    # Bind desk_task_3 as the bed0up override per the Phase 1+2
    # plan (vision/sensor primary; this button is the "stop being
    # silent" override for false-negatives). Declarative — does NOT
    # mutate the live agent.org. Kim's manual `:BUTTON:` drawer
    # entry on bed0up would still win if she sets one.
    defaultButtonBindings = {
      bed0up = "desk_task_3";
    };
  };

  # Cloud model tiers (via historian's ollama, which proxies to ollama cloud):
  #   main agent brain  -> kimi-k2.7-code:cloud   (sonnet/opus tier)
  #   judgment + vision -> gemma4:31b-cloud        (haiku tier; vision-capable)
  # Local gemma4:12b was retired from these roles: the AMD iGPU could not
  # finish a multi-turn agent generation inside the 15-min systemd cycle,
  # leaving lifecoach-heartbeat stuck "activating". Cloud finishes each
  # call in single-digit seconds. think:false is set in the repo call sites
  # (without it, thinking-capable models burn the token budget on reasoning
  # and return empty content).
  #
  # Also make emacsclient findable — the module's default `path =` doesn't
  # include it because the lifecoach-organism flake has no dependency on org-agent.
  systemd.services = lib.mkMerge [
    (lib.genAttrs lifecoach-services (_: {
      environment = {
        OLLAMA_MODEL = lib.mkForce "kimi-k2.7-code:cloud";
        LIFECOACH_JUDGMENT_MODEL = lib.mkForce "gemma4:31b-cloud";
        LIFECOACH_VISION_MODEL = lib.mkForce "gemma4:31b-cloud";
      };
      path = lib.mkAfter [org-agent-emacs];
    }))
    # Stop the old org-life-coach python daemon. Setting wantedBy=[]
    # removes the multi-user.target.wants symlink so it's no longer
    # "wanted" by systemd on boot. But NixOS activation won't stop a
    # currently-running unit whose unit file still exists in the new
    # config (the old module still defines it under cfg.enable, which
    # we keep true to preserve the emacs daemon). So we also need the
    # activation script below to stop it imperatively during switch.
    { org-life-coach.wantedBy = lib.mkForce []; }
  ];

  # ------------------------------------------------------------------
  # Cutover: disable the old org-life-coach services while keeping
  # the org-agent emacs daemon alive. The emacs daemon is defined
  # separately inside the old module and is not gated on these
  # overrides, so it stays running.
  # ------------------------------------------------------------------

  # Null out the bot token options. The old module's systemd unit
  # definitions are inside `lib.mkIf (cfg.matrixBotTokenFile != null)`
  # so setting them to null removes those units entirely from the
  # new system config — nixos-rebuild will stop them on switch.
  services.org-life-coach.matrixBotTokenFile = lib.mkForce null;
  services.org-life-coach.discordBotTokenFile = lib.mkForce null;
  # (matrixBotTokenFile is still an option on the OLD org-life-coach
  # module; the lifecoach-organism module no longer has it. Leave
  # the null override so the old units stay stopped.)

  # Disable the old dashboard the same way (sub-option).
  services.org-life-coach.dashboard.enable = lib.mkForce false;

  system.activationScripts.stop-old-org-life-coach = {
    text = ''
      if /run/current-system/sw/bin/systemctl is-active --quiet org-life-coach.service 2>/dev/null; then
        echo "stopping old org-life-coach daemon (cutover to lifecoach-organism)"
        /run/current-system/sw/bin/systemctl stop org-life-coach.service || true
      fi
    '';
    deps = [];
  };
}
