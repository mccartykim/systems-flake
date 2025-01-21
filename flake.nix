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
    stylix.url = "github:danth/stylix";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    srvos.url = "github:nix-community/srvos";
    srvos.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nixos-hardware,
    nil-flake,
    stylix,
    nix-darwin,
    srvos,
    nix-index-database,
    ...
  } @ inputs: let
    inherit (self) outputs;
  in {
    darwinConfigurations = {
      "kmccarty-YM2K" = nix-darwin.lib.darwinSystem {
        modules = [
          ./darwin/kmccarty-YM2K/configuration.nix
          home-manager.darwinModules.home-manager
          ./darwin/kmccarty-YM2K/default.nix
          ./home/work-laptop.nix
          nix-index-database.darwinModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
        ];
      };
      "cronut" = nix-darwin.lib.darwinSystem {
        modules = [
          ./darwin/cronut/configuration.nix
          home-manager.darwinModules.home-manager
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
      marshmallow = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
          srvos.nixosModules.desktop
          srvos.nixosModules.mixins-trusted-nix-caches
          srvos.nixosModules.mixins-terminfo
          stylix.nixosModules.stylix
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
          {programs.nix-index-database.comma.enable = true;}
          home-manager.nixosModules.home-manager
          {
            home-manager.backupFileExtension = "backup";
            # home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.kimb = ./home/total-eclipse.nix;
          }
          stylix.nixosModules.stylix
        ];
      };
      rich-evans = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
          ./hosts/hp-server/configuration.nix
          stylix.nixosModules.stylix
          nix-index-database.nixosModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
        ];
      };
      bartleby = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
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
            home-manager.users.kimb = import ./hosts/bartleby/home.nix;
          }
          stylix.nixosModules.stylix
          nix-index-database.nixosModules.nix-index
          {programs.nix-index-database.comma.enable = true;}
        ];
      };
    };

    devShell.x86_64-linux = let
      system = "x86_64-linux";
      pkgs = import nixpkgs {inherit system;};
    in
      pkgs.mkShell {
        packages = [pkgs.tealdeer];
      };
  };
}
