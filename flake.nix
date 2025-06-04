{
  description = "Kimb's system flakes";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Nil lsp thingy
    nil-flake.url = "github:oxalica/nil";

    # Home manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    srvos.url = "github:nix-community/srvos";
    srvos.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nixos-avf.url = "github:nix-community/nixos-avf";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nixos-hardware,
    nil-flake,
    nix-darwin,
    srvos,
    nix-index-database,
    nixos-avf,
    ...
  } @ inputs: let
    inherit (self) outputs;
  in {
    darwinConfigurations = {
      "kmccarty-YM2K" = nix-darwin.lib.darwinSystem {
        modules = [
          srvos.darwinModules.desktop
          srvos.darwinModules.mixins-nix-experimental
          srvos.darwinModules.mixins-trusted-nix-caches
          home-manager.darwinModules.home-manager
          ./darwin/kmccarty-YM2K/configuration.nix
          ./home/work-laptop.nix
          nix-index-database.darwinModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
        ];
      };
      "cronut" = nix-darwin.lib.darwinSystem {
        modules = [
          srvos.darwinModules.desktop
          srvos.darwinModules.mixins-nix-experimental
          srvos.darwinModules.mixins-trusted-nix-caches
          home-manager.darwinModules.home-manager
          ./darwin/cronut/configuration.nix
          ./home/cronut.nix
          nix-index-database.darwinModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
        ];
      };
    };

    formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;
    formatter.x86_64-darwin = nixpkgs.legacyPackages.x86_64-darwin.alejandra;

    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;

    # NixOS configuration entrypoint
    # Available through 'nixos-rebuild --flake .#your-hostname'
    nixosConfigurations = {
      bonbon = inputs.nixpkgs.lib.nixosSystem {
        # system to build for
        system = "aarch64-linux";
        # modules to use
        modules = [
          ./avd/bonbon/configuration.nix # our previous config file
          home-manager.nixosModules.home-manager # make home manager available to configuration.nix
          {
            # use system-level nixpkgs rather than the HM private ones
            # "This saves an extra Nixpkgs evaluation, adds consistency, and removes the dependency on NIX_PATH, which is otherwise used for importing Nixpkgs."
            home-manager.useGlobalPkgs = true;
            home-manager.users.droid = ./home/bonbon.nix;
            home-manager.backupFileExtension = "backup";
          }
          nixos-avf.nixosModules.avf
          nix-index-database.nixosModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
        ];
      };

      marshmallow = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
          srvos.nixosModules.desktop
          srvos.nixosModules.mixins-trusted-nix-caches
          srvos.nixosModules.mixins-terminfo
          srvos.nixosModules.mixins-systemd-boot
          srvos.nixosModules.mixins-nix-experimental
          srvos.nixosModules.mixins-trusted-nix-caches
          nixos-hardware.nixosModules.lenovo-thinkpad-t490
          ./hosts/marshmallow/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.backupFileExtension = "backup";
            # home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.kimb = ./home/marshmallow.nix;
          }
          nix-index-database.nixosModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
        ];
      };
      total-eclipse = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
          ./hosts/total-eclipse/configuration.nix
          nix-index-database.nixosModules.nix-index
          srvos.nixosModules.desktop
          srvos.nixosModules.mixins-nix-experimental
          srvos.nixosModules.mixins-trusted-nix-caches
          {programs.nix-index-database.comma.enable = true;}
          home-manager.nixosModules.home-manager
          {
            home-manager.backupFileExtension = "backup";
            # home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.kimb = ./home/total-eclipse.nix;
          }
        ];
      };
      historian = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
          ./hosts/historian/configuration.nix
          nix-index-database.nixosModules.nix-index
          srvos.nixosModules.desktop
          srvos.nixosModules.mixins-nix-experimental
          srvos.nixosModules.mixins-trusted-nix-caches
          {programs.nix-index-database.comma.enable = true;}
          home-manager.nixosModules.home-manager
          {
            home-manager.backupFileExtension = "backup";
            # home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.kimb = ./home/historian.nix;
          }
        ];
      };
      rich-evans = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
          ./hosts/rich-evans/configuration.nix
          srvos.nixosModules.server
          srvos.nixosModules.mixins-trusted-nix-caches
          srvos.nixosModules.mixins-systemd-boot
          srvos.nixosModules.mixins-nix-experimental
          nix-index-database.nixosModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
        ];
      };
      bartleby = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          srvos.nixosModules.desktop
          srvos.nixosModules.mixins-systemd-boot
          srvos.nixosModules.mixins-nix-experimental
          srvos.nixosModules.mixins-trusted-nix-caches
          nixos-hardware.nixosModules.lenovo-thinkpad
          {
            nixpkgs.overlays = [
              nil-flake.overlays.nil
            ];
          }
          ./hosts/bartleby/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.backupFileExtension = "backup";
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.kimb = ./home/bartleby.nix;
          }
          nix-index-database.nixosModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
        ];
      };
    };

    devShells.x86_64-linux.default = let
      system = "x86_64-linux";
      pkgs = import nixpkgs {inherit system;};
    in
      pkgs.mkShell {
        packages = [pkgs.tealdeer];
      };
  };
}
