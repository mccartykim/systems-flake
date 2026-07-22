# Colmena deployment configuration
{
  inputs,
  self,
  ...
}: let
  inherit (inputs) nixpkgs;
  registry = import (self + "/hosts/nebula-registry.nix");

  # Only include hosts that have a nixosConfiguration (auto-filters non-NixOS hosts)
  nixosHosts = builtins.intersectAttrs self.nixosConfigurations registry.nodes;

  # Helper to create colmena node from registry entry
  makeColmenaNode = name: node: {
    deployment = {
      # Most hosts: deploy over Nebula. maitred is the DNS/Nebula authority
      # itself, and its sshd doesn't reliably bind to the Nebula address at
      # boot — reach it on the LAN router IP instead.
      targetHost =
        if name == "maitred"
        then "192.168.69.1"
        else "${name}.nebula";
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
          inherit inputs;
          outputs = self;
          # Parity with nixosConfigurations' mkServer `extraSpecialArgs`: the
          # org-bridge module (on rich-evans, loaded via the shared modules
          # in makeColmenaNode `imports`) takes { bridgeCrewSrc } as a module
          # arg. nixosConfigurations threads it via mkServer; colmena sets its
          # own specialArgs here, so without this `deploy rich-evans` (colmena)
          # fails "attribute 'bridgeCrewSrc' missing" while `nswitch` works.
          bridgeCrewSrc = inputs."bridge-crew-src";
        };
      };
    }
    // (builtins.mapAttrs makeColmenaNode nixosHosts);
}
