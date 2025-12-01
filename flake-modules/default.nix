# Flake-parts modules for organizing the flake
# Each module defines a portion of the flake outputs
{
  imports = [
    ./helpers.nix
    ./nixos-configurations.nix
    ./darwin-configurations.nix
    ./colmena.nix
    ./system-manager.nix
  ];
}
