# System-manager configurations for non-NixOS hosts
{inputs, self, ...}: let
  inherit (inputs) system-manager;
in {
  flake.systemConfigs = {
    oracle = system-manager.lib.makeSystemConfig {
      modules = [(self + "/hosts/oracle/configuration.nix")];
    };
  };
}
