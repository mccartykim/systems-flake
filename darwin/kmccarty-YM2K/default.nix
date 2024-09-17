## Use this file to specify nix-darwin options,
## which are mostly configuration changes to MacOS. You mayyyy need to rerun
## `darwin-rebuild switch --flake $THIS_FLAKE` after MacOS updates
{
  pkgs,
  config,
  lib,
  ...
}: let
  corretto17 = pkgs.fetchzip {
    name = "corretto17";
    url = "https://corretto.aws/downloads/latest/amazon-corretto-17-aarch64-macos-jdk.tar.gz";
    hash = "1ahi1zkd8kgzq1ksgwwn7pw59a9mppgdsw6z4j6i7r1vna0s8rf1";
  };
in {
  # DO NOT SET ENVIRONMENTAL VARIABLES ELSEWHERE
  launchd.user.envVariables = {
    ANDROID_HOME = "/Users/kimberly.mccarty/Library/Android/sdk/";
    JAVA_HOME = "${corretto17}/Contents/Home/";
  };

  programs.fish.enable = true;
  system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";
}
