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
  # For some reason, nix-darwin needs this stated explicitly
  users.users."kimberly.mccarty".home = "/Users/kimberly.mccarty";
  users.users."kimberly.mccarty".shell = pkgs.fish;
  system.primaryUser = "kimberly.mccarty";
  nixpkgs = {
    config = {
      allowBroken = true;
      allowUnfree = true;
    };
    flake.setNixPath = true;
    flake.setFlakeRegistry = true;
    hostPlatform = "aarch64-darwin";
  };
  environment.systemPackages = [
    pkgs.terminal-notifier
    pkgs.cachix
    pkgs.scrcpy
    pkgs.lazygit
    pkgs.nix-output-monitor
    pkgs.emacs
    pkgs.gnupg
  ];
  nix = {
    nixPath = pkgs.lib.mkForce [
      {
        darwin-config = builtins.concatStringsSep ":" [
          "$HOME/.nixpkgs/darwin-configuration.nix"
          "$HOME/.nix-defexpr/channels"
        ];
      }
    ];
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      substituters = [
      ];
      trusted-public-keys = [
      ];
      trusted-users = [ "@admin" ];
    };
    optimise.automatic = true;
    gc = {
      automatic = true;
      interval = [
        {
          Hour = 17;
          Minute = 0;
          Weekday = 5;
        }
      ];
    };
  };

  programs.gnupg.agent.enable = true;

  launchd.daemons.nix-darwin-activate = {
    serviceConfig = {
      ProgramArguments = [ "/var/run/current-system/activate" ];
      RunAtLoad = true;
      KeepAlive = false;
      UserName = "root";
      StandardOutPath = "/var/log/nix-darwin-activate.log";
      StandardErrorPath = "/var/log/nix-darwin-activate.log";
    };
  };
  security.pam.services.sudo_local.touchIdAuth = true;

  programs.nix-index.enable = true;
  services.emacs.enable = true;

  # fonts.fontDir.enable = true;
  fonts.packages = with pkgs; [
    nerd-fonts.recursive-mono
    nerd-fonts.jetbrains-mono
    nerd-fonts.inconsolata
    nerd-fonts.intone-mono
  ];

  # Set Git commit hash for darwin-version.
  # system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # From original default.nix
  launchd.user.envVariables = sharedEnv;
  # For shell only
  environment.variables = {
    EDITOR = "hx";
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
