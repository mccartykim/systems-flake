{pkgs, ...}: {
  imports = [./default.nix];

  # For some reason, nix-darwin needs this stated explicitly
  users.users."kimberly.mccarty".home = "/Users/kimberly.mccarty";
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
      experimental-features = ["nix-command" "flakes"];
      substituters = [
        "https://cache.garnix.io"
      ];
      trusted-public-keys = [
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
      trusted-users = ["@admin"];
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

  launchd.daemons.nix-darwin-activate = {
    serviceConfig = {
      ProgramArguments = ["/var/run/current-system/activate"];
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
}
