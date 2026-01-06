# Darwin (macOS) configurations
{
  inputs,
  config,
  ...
}: let
  inherit (inputs) nix-darwin;
  inherit (config.flake.lib) darwinCommon;
in {
  flake.darwinConfigurations = {
    "kmccarty-27YM2K" = nix-darwin.lib.darwinSystem {
      modules =
        darwinCommon
        ++ [
          ../darwin/kmccarty-YM2K/configuration.nix
          ../home/work-laptop.nix
        ];
    };

    "cronut" = nix-darwin.lib.darwinSystem {
      modules =
        darwinCommon
        ++ [
          ../darwin/cronut/configuration.nix
          ../home/cronut.nix
        ];
    };
  };
}
