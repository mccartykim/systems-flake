# Host enablement for the Void-Master (Idran, fleet-fixer) on rich-evans.
#
# The module definition ships from the voidmaster_organism flake as
# nixosModules.default (self-contained — provides its own package,
# mirroring vacuum_organism). This file is config-only, mirroring
# hosts/rich-evans/vacuum-organism.nix's host-enabling shape.
#
# Phase 1: the officer's comms path is the vox-bridge Matrix transport
# (hosts/rich-evans/voidmaster-vox-bridge.nix). The module's own Discord
# sidecar (discordBotTokenFile) is the Phase-2 target shape and is left
# null here.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  services.voidmaster-organism = {
    enable = true;
    stateDir = "/var/lib/voidmaster-organism";
    systemsFlakeDir = "/home/kimb/shared_projects/systems-flake";
    ollamaHost = "http://historian.nebula:11434";
    ollamaModel = "kimi-k2.7-code:cloud";
    # Phase 1 uses the vox-bridge; leave the Phase-2 Discord sidecar off.
    discordBotTokenFile = null;
  };
}