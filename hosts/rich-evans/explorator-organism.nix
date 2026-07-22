# Host enablement for the Magos Explorator (Velan, machine-spirit
# diagnostician) on rich-evans.
#
# The module definition ships from the explorator_organism flake as
# nixosModules.default (self-contained — provides its own package,
# mirroring confessor_organism / factotum_organism). This file is
# config-only, mirroring hosts/rich-evans/confessor-organism.nix's
# host-enabling shape.
#
# Differences from the Confessor host file:
#   - No systemsFlakeDir: the Explorator holds no checkout; crew state
#     reaches it via the sibling .organism/ snapshot reliquaries (read
#     through group membership), not a local flake. The SPEC block
#     degrades to a static pointer (organism repo is PRIVATE; the service
#     user has no github credential).
#   - No Discord sidecar: the Explorator's comms path is a vox-bridge
#     instance (Phase 1.5); the module exposes no discordBotTokenFile.
#   - Weekly health-audit (OnCalendar Mon 03:30), not a nightly examen —
#     the Explorator is SUMMONED, not a heartbeat. The seed is #+LOOP: none
#     + a calendar-driven systemd TIMER (the loop-bug fix). The comms bridge
#     may also summon it on demand with a petition (EXPLORATOR_QUERY focuses
#     the ARCHEOTECH nixpkgs hunt).
#   - uid 991 (fixed; sits after confessor-organism 990 in the bridge-crew
#     service-user cluster: voidmaster 987, nebula-mesh 988, factotum 989,
#     confessor 990) so org-bridge can map it via SO_PEERCRED before first
#     activation.
#   - READ grants (module extraGroups): the sibling officer groups
#     (voidmaster/factotum/confessor/life-coach/vacuum) so the RELIQUARY +
#     COGITATION blocks can read their .organism/ snapshot dirs + live seeds.
#     NO systemd-journal — the Explorator reads no journals (UTTERANCES is
#     the Confessor's rite, not the machine-spirit diagnostician's domain).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.explorator-organism = {
    enable = true;
    stateDir = "/var/lib/explorator-organism";
    ollamaHost = "http://historian.nebula:11434";
    ollamaModel = "kimi-k2.7-code:cloud";
    # Weekly health-audit Monday 03:30 local (the module default; restated
    # here for clarity). Persistent=true catches a missed audit.
    auditCalendar = "Mon *-*-* 03:30:00";
  };
}