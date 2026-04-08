# lifecoach-organism: full cutover from org-life-coach.
#
# This file does two things:
#
# 1. Turns on lifecoach-organism with the full feature set
#    (button monitor, matrix/discord bots, cameras, dashboard).
#
# 2. Disables the old org-life-coach python daemon, matrix/discord
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
in {
  services.lifecoach-organism = {
    enable = true;
    user = "life-coach";
    stateDir = "/var/lib/lifecoach-organism";

    # Heartbeat every 1h. This is the safety net in case the
    # LOOP_AT scheduling chain breaks (e.g. a transient API error
    # causes a scheduled cycle to fail without emitting a new
    # LOOP_AT — first time we saw this happen on 04-08 after an
    # Anthropic 500). A 1h ceiling means the worst case is an hour
    # of silence before the heartbeat re-primes the agent.
    heartbeatInterval = "1h";

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
    ttsVoice = "jet2";
    ttsDevice = "Kim's nest hub";

    # Full cutover: everything on.
    enableButtonMonitor = true;

    matrixHomeserver = "http://127.0.0.1:6167";
    matrixBotUser = "@lifecoach:kimb.dev";
    matrixBotTokenFile = config.age.secrets.matrix-life-coach-token.path;
    matrixAllowedSenders = "@kimb:kimb.dev";

    discordBotTokenFile = config.age.secrets.discord-life-coach-token.path;
    # discordAllowedUsers left empty = allow all

    # Cameras — same URLs the old daemon was using.
    cameraBedUrl = "http://127.0.0.1:8554/cam0";
    cameraDeskUrl = "http://127.0.0.1:8554/cam1";

    # Dashboard stays on 8586 for now — taking over 8585 requires
    # stopping the old dashboard first which we're doing below,
    # but cross-service port renegotiation in a single activation
    # is fragile. Leave old URL dead and Kim can bookmark 8586.
    dashboard = {
      enable = true;
      port = 8586;
      openFirewall = true;
    };
  };

  # Make emacsclient findable from every lifecoach service. The
  # module's default `path =` doesn't include it because the
  # lifecoach-organism flake has no dependency on org-agent.
  systemd.services.lifecoach-heartbeat.path       = lib.mkAfter [org-agent-emacs];
  systemd.services.lifecoach-scheduler.path       = lib.mkAfter [org-agent-emacs];
  systemd.services.lifecoach-dashboard.path       = lib.mkAfter [org-agent-emacs];
  systemd.services.lifecoach-button-monitor.path  = lib.mkAfter [org-agent-emacs];
  systemd.services.lifecoach-matrix-bot.path      = lib.mkAfter [org-agent-emacs];
  systemd.services.lifecoach-discord-bot.path     = lib.mkAfter [org-agent-emacs];

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
  services.org-life-coach.matrixBotTokenFile  = lib.mkForce null;
  services.org-life-coach.discordBotTokenFile = lib.mkForce null;

  # Disable the old dashboard the same way (sub-option).
  services.org-life-coach.dashboard.enable = lib.mkForce false;

  # Stop the main python daemon itself. Setting wantedBy=[] removes
  # the multi-user.target.wants symlink so it's no longer "wanted"
  # by systemd, and on activation NixOS will stop it because the
  # previous config's wantedBy referenced it. The service unit
  # file stays (since the old module still defines it under
  # cfg.enable), but nothing starts it.
  systemd.services.org-life-coach.wantedBy = lib.mkForce [];
}
