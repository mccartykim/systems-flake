# Darwin (macOS) configurations
{
  inputs,
  config,
  ...
}:
let
  inherit (inputs) nix-darwin;
  inherit (config.flake.lib) darwinCommon;
in
{
  flake.darwinConfigurations = {
    "cronut" = nix-darwin.lib.darwinSystem {
      modules = darwinCommon ++ [
        ../darwin/cronut/configuration.nix
        ../home/cronut.nix
      ];
    };
  };
}
