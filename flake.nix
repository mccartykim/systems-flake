{
  description = "Kimb's system flakes";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home manager
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixvim = {
      url = "github:nix-community/nixvim";
      # If you are not running an unstable channel of nixpkgs, select the corresponding branch of nixvim.
      # url = "github:nix-community/nixvim/nixos-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    nixos-hardware,
    nixvim,
    ...
  } @ inputs: let
    inherit (self) outputs;
  in {
    # NixOS configuration entrypoint
    # Available through 'nixos-rebuild --flake .#your-hostname'
    nixosConfigurations = {
      marshmallow = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
	  ./hosts/marshmallow/configuration.nix
          nixos-hardware.nixosModules.lenovo-thinkpad-t490
	];
      };
      total-eclipse = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        # > our main nixos configuration file <
        modules = [
	  ./hosts/total-eclipse/configuration.nix
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
  };
}
