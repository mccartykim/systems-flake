# Colmena deployment configuration
{
  inputs,
  self,
  ...
}: let
  inherit (inputs) nixpkgs copyparty claude_yapper kokoro;
  registry = import (self + "/hosts/nebula-registry.nix");

  # Only include hosts that have a nixosConfiguration (auto-filters non-NixOS hosts)
  nixosHosts = builtins.intersectAttrs self.nixosConfigurations registry.nodes;

  # Helper to create colmena node from registry entry
  makeColmenaNode = name: node: {
    deployment = {
      # Use hostname.nebula for DNS resolution, fallback comment shows IP
      # ${name}.nebula resolves via maitred DNS, or use node.ip (${node.ip}) directly
      targetHost = "${name}.nebula";
      targetUser = "kimb";
      buildOnTarget = false;
    };
    imports = self.nixosConfigurations.${name}._module.args.modules;
  };
in {
  flake.colmena =
    {
      meta = {
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = [];
        };
        specialArgs = {
          inherit inputs copyparty claude_yapper kokoro;
          outputs = self;
        };
      };
    }
    // (builtins.mapAttrs makeColmenaNode nixosHosts);
}
