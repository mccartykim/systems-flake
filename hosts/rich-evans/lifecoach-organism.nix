# lifecoach-organism: parallel-operation proof-of-concept deploy.
#
# Runs the new organism-based life coach agent alongside the
# existing org-life-coach Python daemon. Intentionally minimal
# for a first deploy:
#
# - Button monitor OFF — old daemon keeps handling physical presses
# - Matrix/Discord bots OFF — old bots keep handling chat
# - Dashboard ON at port 8586 (old dashboard stays on 8585)
# - Heartbeat every 4h (gentle, not pushy)
# - HA state + task view + TTS all wired
# - Camera URLs unset (HA state alone drives situational awareness)
#
# Rollback: set enable = false and redeploy. Old daemon is
# untouched by this file so it stays working the whole time.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  # Reuse the existing org-agent emacs build from the upstream
  # org-agent flake input. Needed on the PATH of every lifecoach
  # service that calls emacsclient (build-view babel block,
  # org-task write verbs, dashboard /api/agenda).
  org-agent-emacs = inputs.org-agent.packages.${pkgs.system}.emacs;
in {
  services.lifecoach-organism = {
    enable = true;
    user = "life-coach";
    stateDir = "/var/lib/lifecoach-organism";

    # Agent cadence: slow safety-net heartbeat. Scheduled wakeups
    # the agent requests via #+LOOP_AT fire on their own schedule.
    heartbeatInterval = "4h";

    # Home Assistant — reuse the existing agenix secret
    haUrl = "http://127.0.0.1:8123";
    haTokenFile = config.age.secrets.ha-life-coach-token.path;

    # Talk to the existing org-agent emacs daemon for task view
    # and org-task writes.
    orgAgentSocket = "/var/lib/life-coach-agent/emacs/org-agent";
    orgAgentEmacsclient = "${org-agent-emacs}/bin/emacsclient";

    # TTS defaults — Qwen server on total-eclipse, bajoran voice,
    # default device Kim's nest hub. Keep the "jet2" voice used
    # by the current prod deploy.
    ttsServer = "http://total-eclipse.nebula:8091";
    ttsVoice = "jet2";
    ttsDevice = "Kim's nest hub";

    # PARALLEL-MODE SAFEGUARDS:
    # These capabilities are intentionally left to the old daemon
    # during parallel operation. Flip to true + set the respective
    # token files when doing a full cutover.
    enableButtonMonitor = false;
    # matrixBotTokenFile = null;   # default
    # discordBotTokenFile = null;  # default

    # Dashboard on a separate port from the old one (8585).
    dashboard = {
      enable = true;
      port = 8586;
      openFirewall = true;
    };
  };

  # Make emacsclient findable from every lifecoach service. The
  # module's default `path =` doesn't include it because the
  # lifecoach-organism flake has no dependency on org-agent — we
  # wire it here at the host level where the dependency exists.
  systemd.services.lifecoach-heartbeat.path  = lib.mkAfter [org-agent-emacs];
  systemd.services.lifecoach-scheduler.path  = lib.mkAfter [org-agent-emacs];
  systemd.services.lifecoach-dashboard.path  = lib.mkAfter [org-agent-emacs];
}
