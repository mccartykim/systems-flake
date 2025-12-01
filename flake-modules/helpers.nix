# Helper functions and common module lists for NixOS configurations
{
  inputs,
  self,
  ...
}: let
  inherit (inputs) nixpkgs home-manager srvos nix-index-database;
in {
  # Export helpers via flake.lib for use by other modules
  flake.lib = rec {
    # Common modules applied to all NixOS configurations
    commonModules = [
      nix-index-database.nixosModules.nix-index
      {programs.nix-index-database.comma.enable = true;}
      (self + "/modules/distributed-builds.nix")
      {kimb.distributedBuilds.enable = true;}
      (self + "/modules/agenix.nix")
    ];

    # Desktop-specific modules (srvos desktop + common mixins)
    desktopModules = [
      srvos.nixosModules.desktop
      srvos.nixosModules.mixins-nix-experimental
      srvos.nixosModules.mixins-trusted-nix-caches
    ];

    # Server-specific modules
    serverModules = [
      srvos.nixosModules.server
      srvos.nixosModules.mixins-nix-experimental
      srvos.nixosModules.mixins-trusted-nix-caches
      srvos.nixosModules.mixins-systemd-boot
    ];

    # Darwin common modules
    darwinCommon = [
      home-manager.darwinModules.home-manager
      nix-index-database.darwinModules.nix-index
      {programs.nix-index-database.comma.enable = true;}
    ];

    # Home-manager configuration helper
    mkHomeManager = {
      user ? "kimb",
      homeConfig,
      useGlobalPkgs ? false,
    }: [
      home-manager.nixosModules.home-manager
      {
        home-manager = {
          backupFileExtension = "backup";
          inherit useGlobalPkgs;
          useUserPackages = true;
          users.${user} = homeConfig;
        };
      }
    ];

    # Helper to create a desktop NixOS configuration
    mkDesktop = {
      hostname,
      system ? "x86_64-linux",
      extraModules ? [],
      hardwareModules ? [],
      homeConfig ? (self + "/home/${hostname}.nix"),
      useGlobalPkgs ? false,
    }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs; outputs = self;};
        modules =
          desktopModules
          ++ commonModules
          ++ hardwareModules
          ++ [(self + "/hosts/${hostname}/configuration.nix")]
          ++ mkHomeManager {inherit homeConfig useGlobalPkgs;}
          ++ extraModules;
      };

    # Helper to create a server NixOS configuration
    mkServer = {
      hostname,
      system ? "x86_64-linux",
      extraModules ? [],
      extraSpecialArgs ? {},
    }:
      nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs; outputs = self;} // extraSpecialArgs;
        modules =
          serverModules
          ++ commonModules
          ++ [(self + "/hosts/${hostname}/configuration.nix")]
          ++ extraModules;
      };
  };
}
