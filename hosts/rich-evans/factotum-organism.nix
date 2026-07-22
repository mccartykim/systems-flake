# Host enablement for the High Factotum (Severin, bookkeeper) on rich-evans.
#
# The module definition ships from the factotum_organism flake as
# nixosModules.default (self-contained — provides its own package,
# mirroring voidmaster_organism / vacuum_organism). This file is
# config-only, mirroring hosts/rich-evans/voidmaster-organism.nix's
# host-enabling shape.
#
# Differences from the Void-Master host file:
#   - No systemsFlakeDir: the Factotum's HOLDINGS/DRIFT blocks read the
#     PUBLIC systems-flake from github via `nix flake metadata` (pure,
#     no checkout) — the module exposes no systemsFlakeDir option and
#     sets no SYSTEMS_FLAKE env. Under colmena the fleet source is not
#     on the deployed host anyway, and the officer service user cannot
#     traverse /home/kimb to a local checkout.
#   - No Discord sidecar: the Factotum's comms path is a vox-bridge
#     instance (Phase 1.5); the module exposes no discordBotTokenFile.
#   - Daily (24h) heartbeat, not 30m — the holds are recounted once per
#     watch, not every bell. The seed is #+LOOP: none + a 24h systemd
#     TIMER (the loop-bug fix, mirroring the Void-Master).
#   - uid 989 (fixed; sits after voidmaster-organism 987 + nebula-mesh
#     988 in the fleet service-user cluster) so org-bridge can map it
#     via SO_PEERCRED before first activation.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.factotum-organism = {
    enable = true;
    stateDir = "/var/lib/factotum-organism";
    ollamaHost = "http://historian.nebula:11434";
    ollamaModel = "kimi-k2.7-code:cloud";
    # Daily ledger recount (the module default; restated here for clarity).
    heartbeatInterval = "24h";
  };
}