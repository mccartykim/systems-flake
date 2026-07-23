# Host enablement for the Navigator (Orlena, read-only strategic planner)
# on total-eclipse — the CROSS-HOST bridge officer.
#
# The module definition ships from the navigator_organism flake as
# nixosModules.default (self-contained — provides its own package,
# mirroring confessor_organism). This file is config-only.
#
# Differences from the Confessor host file (rich-evans):
#   - Hosted on total-eclipse, NOT rich-evans — the first officer off the
#     bridge-crew host. The comms bridge (vox-organism, on rich-evans)
#     reaches this officer by SSH-dispatching a cycle to this host (the
#     #navigator Matrix presence path; deploy hinge, wired separately).
#   - No fixed uid: the Navigator skips org-bridge (reaching the rich-evans
#     broker cross-host would punch a trust hole to a 2nd host), so there is
#     no SO_PEERCRED uid->officer map to populate. NixOS auto-assigns.
#   - No READ grants (no systemd-journal, no reliquaryGroups): the
#     RELICS/UTTERANCES/SOULS blocks are dropped (they read rich-evans local
#     services + .organism/ snapshots, not on this host). The Navigator
#     charts from the repo ecosystem alone (PUBLIC github reads).
#   - 4h strategic-planning heartbeat (OnUnitActiveSec=4h), not the
#     Confessor's nightly 22:00 examen — a planner sounds the depth oftener
#     than a chronicler sets down the watch. The seed is #+LOOP: none + a
#     systemd TIMER (the loop-bug fix).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.navigator-organism = {
    enable = true;
    stateDir = "/var/lib/navigator-organism";
    ollamaHost = "http://historian.nebula:11434";
    ollamaModel = "kimi-k2.7-code:cloud";
    # 4h strategic-planning heartbeat (the module default; restated for
    # clarity). Persistent=true catches a missed sounding if the host was
    # down. Cloud model only (no local inference) so the timer does not
    # contend with the desktop's GPU.
    heartbeatInterval = "4h";
  };
}