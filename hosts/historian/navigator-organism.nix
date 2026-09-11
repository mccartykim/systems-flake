# Host enablement for the Navigator (Orlena, read-only strategic planner)
# on historian — the CROSS-HOST bridge officer. Moved here from total-eclipse
# at a3j.9.3 so that host can sleep.
#
# The module definition ships from the navigator_organism flake as
# nixosModules.default (self-contained — provides its own package, mirroring
# confessor_organism). This file is config-only.
#
# The comms bridge (vox-organism, on rich-evans) reaches this officer by
# SSH-dispatching a cycle to this host via the navigator-summon forced command
# (the module wires that onto the shared bridge-fleet key). No fixed uid: the
# Navigator skips org-bridge (reaching a broker cross-host would punch a trust
# hole), so there is no SO_PEERCRED uid->officer map to populate.
# 4h strategic-planning heartbeat (the module default); cloud model only so the
# timer does not contend with the desktop GPU.
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
    heartbeatInterval = "4h";
  };
}
