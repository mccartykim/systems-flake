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
      # historian builds its own closure on-target: it's the 24-core build
      # machine and already holds the heavy store paths its closure references
      # (e.g. the ROCm aotriton/torch kernels), so building there reuses them
      # instead of rebuilding from source on the deployer (total-eclipse) after
      # a local GC evicts them — and without the per-derivation round-trip
      # latency of nix.distributedBuilds. Other hosts build on the deployer:
      # rich-evans is too weak to self-build, and its closure is light enough
      # for total-eclipse. Override per-invocation with --[no-]build-on-target.
      buildOnTarget = name == "historian";
    };
    imports = self.nixosConfigurations.${name}._module.args.modules;
  };

  hive = {
    meta = {
      nixpkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [];
      };
      specialArgs = {
        inherit inputs;
        outputs = self;
      };
    };
  } // (builtins.mapAttrs makeColmenaNode nixosHosts);
in {
  # Colmena 0.5 changed its flake output in two ways: it reads `colmenaHive`
  # instead of `colmena`, and it asserts that the hive declares
  # `__schema == "v0.5"`. A hive without that field fails with
  # `attribute '__schema' missing`. nixpkgs pins 0.5.0, so the repo's `deploy`
  # devshell alias was broken against it.
  #
  # The two outputs therefore differ by exactly that field. It is NOT added to
  # the legacy `colmena` output: colmena 0.4 predates the schema and would read
  # an extra `__schema` key as a node named "__schema" whose config is a string,
  # so adding it there would break the version it still serves.
  flake.colmena = hive;
  flake.colmenaHive = hive // {__schema = "v0.5";};
}
