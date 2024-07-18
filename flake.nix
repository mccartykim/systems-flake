{
  description = "Kimb's system flakes";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Nil lsp thingy
    nil-flake.url = "github:oxalica/nil";

    # Home manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixvim = {
      url = "github:nix-community/nixvim";
      # If you are not running an unstable channel of nixpkgs, select the corresponding branch of nixvim.
      # url = "github:nix-community/nixvim/nixos-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix.url = "github:danth/stylix";
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.90.0.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nixos-hardware,
    nixvim,
    nil-flake,
    stylix,
    lix-module,
    ...
  } @ inputs: let
    inherit (self) outputs;
  in {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
    # NixOS configuration entrypoint
    # Available through 'nixos-rebuild --flake .#your-hostname'
    nixosConfigurations = {
      marshmallow = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
	  stylix.nixosModules.stylix
          nixos-hardware.nixosModules.lenovo-thinkpad-t490
          ./hosts/marshmallow/configuration.nix
          home-manager.nixosModules.home-manager
	  {
            # home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
	    home-manager.users.kimb = ./home/marshmallow.nix;
	  }
	  lix-module.nixosModules.default
        ];
      };
      total-eclipse = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
          ./hosts/total-eclipse/configuration.nix
	  lix-module.nixosModules.default
        ];
      };
      rich-evans = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
          ./hosts/hp-server/configuration.nix
	  lix-module.nixosModules.default
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
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.kimb = import ./hosts/bartleby/home.nix;
          }
	  lix-module.nixosModules.default
        ];
      };
    };

    # Standalone home-manager configuration entrypoint
    # Available through 'home-manager --flake .#your-username@your-hostname'
    homeConfigurations = {
      "kimb@marshmallow" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
        extraSpecialArgs = {inherit inputs outputs;};
        # > Our main home-manager configuration file <
        modules = [
          nixvim.homeManagerModules.nixvim
          ./home/marshmallow.nix
        ];
      };
      "kimb@total-eclipse" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
        extraSpecialArgs = {inherit inputs outputs;};
        # > Our main home-manager configuration file <
        modules = [
          nixvim.homeManagerModules.nixvim
          ./home/total-eclipse.nix
        ];
      };
    };
    devShell.x86_64-linux = let
      system = "x86_64-linux";
      pkgs  = import nixpkgs { inherit system; };
    in
    pkgs.mkShell {
      packages = [ pkgs.tealdeer ];
    };
  };
}
