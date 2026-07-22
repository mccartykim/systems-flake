# Host enablement for the Ship's Confessor (Aurelian, fleet chronicler) on
# rich-evans.
#
# The module definition ships from the confessor_organism flake as
# nixosModules.default (self-contained — provides its own package,
# mirroring factotum_organism / voidmaster_organism). This file is
# config-only, mirroring hosts/rich-evans/factotum-organism.nix's
# host-enabling shape.
#
# Differences from the Factotum host file:
#   - No systemsFlakeDir: the Confessor's TRAILS block reads the PUBLIC
#     systems-flake from github via `nix flake metadata` (pure, no
#     checkout) — the module exposes no systemsFlakeDir option. The
#     TOOLING block degrades to a static pointer (organism repo is
#     PRIVATE; the service user has no github credential).
#   - No Discord sidecar: the Confessor's comms path is a vox-bridge
#     instance (Phase 1.5); the module exposes no discordBotTokenFile.
#   - Nightly examen (OnCalendar 22:00), not a 24h interval — the
#     chronicle is set down once per watch at the bell. The seed is
#     #+LOOP: none + a calendar-driven systemd TIMER (the loop-bug fix).
#   - uid 990 (fixed; sits after factotum-organism 989 in the bridge-crew
#     service-user cluster: voidmaster 987, nebula-mesh 988, factotum 989)
#     so org-bridge can map it via SO_PEERCRED before first activation.
#   - READ grants (module extraGroups): systemd-journal (journalctl) +
#     the sibling officer groups (voidmaster/factotum/life-coach/vacuum)
#     so RELICS can read their .organism/ snapshot dirs.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.confessor-organism = {
    enable = true;
    stateDir = "/var/lib/confessor-organism";
    ollamaHost = "http://historian.nebula:11434";
    ollamaModel = "kimi-k2.7-code:cloud";
    # Nightly examen at 22:00 local (the module default; restated here
    # for clarity). Persistent=true catches a missed bell.
    examenCalendar = "*-*-* 22:00:00";
  };
}