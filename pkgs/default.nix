# Custom packages for systems-flake
# This file provides a unified interface for all custom packages
# (eden-nightly is now in the eden-nightly-flake input, not here)
{
  pkgs,
  lib,
}: let
  # Call each package with the appropriate arguments
  claude-zai = pkgs.callPackage ./claude-zai.nix {};
  esp32-firmware = pkgs.callPackage ./esp32-firmware.nix {};
  warewoolf = pkgs.callPackage ./warewoolf {};
  libreboot-e6400-mec5035 = pkgs.callPackage ./libreboot-e6400-mec5035/default.nix {};
  pdx-wallpaper = pkgs.callPackage ./pdx-wallpaper {};
in {
  inherit claude-zai esp32-firmware warewoolf libreboot-e6400-mec5035 pdx-wallpaper;
}
