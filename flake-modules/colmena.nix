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
          # Parity with nixosConfigurations' mkServer `extraSpecialArgs`
          # (rich-evans): the voidmaster-vox-bridge host module takes
          # { organism } for organicBin, and the org-bridge module (from
          # bridge-crew-src, loaded via the shared modules in makeColmenaNode
          # `imports`) takes { bridgeCrewSrc }. nixosConfigurations threads
          # both via mkServer's extraSpecialArgs; colmena sets its own
          # specialArgs here, so without these `deploy rich-evans` (colmena)
          # fails "attribute 'X' missing" while `nswitch rich-evans`
          # (nixosConfigurations) works. Unused by hosts that don't import
          # those modules.
          inherit (inputs) organism;
          bridgeCrewSrc = inputs."bridge-crew-src";
        };
      };
    }
    // (builtins.mapAttrs makeColmenaNode nixosHosts);
}
