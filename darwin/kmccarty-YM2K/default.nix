## Use this file to specify nix-darwin options,
## which are mostly configuration changes to MacOS. You mayyyy need to rerun
## `darwin-rebuild switch --flake $THIS_FLAKE` after MacOS updates
{
  pkgs,
  config,
  lib,
  ...
}:
let
  corretto17 = pkgs.fetchzip {
    name = "corretto17";
    url = "https://corretto.aws/downloads/latest/amazon-corretto-17-aarch64-macos-jdk.tar.gz";
    hash = "sha256-T4eDYeQ3FqQyspa7R0lm1vnC11pNjU2FflV9eh+vPKI=";
  };
  sharedEnv = {
    ANDROID_HOME = "/Users/kimberly.mccarty/Library/Android/sdk/";
    JAVA_HOME = "${corretto17}/Contents/Home/";
    GRADLE_LOCAL_JAVA_HOME = "${corretto17}/Contents/Home/";
  };
in
{
  launchd.user.envVariables = sharedEnv;
  # For shell only
  environment.variables = {
    EDITOR = "emacsclient";
  };

  programs.fish.enable = true;
  system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    users."kimberly.mccarty".home.sessionVariables = sharedEnv;
  };
}
