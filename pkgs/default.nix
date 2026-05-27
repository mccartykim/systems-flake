# Custom packages for systems-flake
# This file provides a unified interface for all custom packages
{
  pkgs,
  lib,
}: let
  # Call each package with the appropriate arguments
  claude-zai = pkgs.callPackage ./claude-zai.nix {};
  esp32-firmware = pkgs.callPackage ./esp32-firmware.nix {};
  eden-master = pkgs.callPackage ./eden-master/default.nix {};
  warewoolf = pkgs.callPackage ./warewoolf {};
in {
  inherit claude-zai esp32-firmware eden-master warewoolf;
}
