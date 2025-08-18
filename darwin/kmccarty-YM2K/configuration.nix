{pkgs, ...}: {
  imports = [./default.nix];

  # For some reason, nix-darwin needs this stated explicitly
  users.users."kimberly.mccarty".home = "/Users/kimberly.mccarty";
  system.primaryUser = "kimberly.mccarty";
  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
  };
  nixpkgs.flake.setNixPath = true;
  nixpkgs.flake.setFlakeRegistry = true;
  environment.systemPackages = [
    pkgs.terminal-notifier
    pkgs.cachix
    pkgs.scrcpy
    pkgs.lazygit
    pkgs.nix-output-monitor
  ];
  nix.nixPath = pkgs.lib.mkForce [
    {
      darwin-config = builtins.concatStringsSep ":" [
        "$HOME/.nixpkgs/darwin-configuration.nix"
        "$HOME/.nix-defexpr/channels"
      ];
    }
  ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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

  # Necessary for using flakes on this system.
  nix.settings.substituters = [
    "https://cache.garnix.io"
  ];
  nix.settings.trusted-public-keys = [
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];

  nix.settings.trusted-users = ["@admin"];

  nix.optimise.automatic = true;
  nix.gc.automatic = true;
  nix.gc.interval = [
    {
      Hour = 17;
      Minute = 0;
      Weekday = 5;
    }
  ];
  security.pam.services.sudo_local.touchIdAuth = true;

  programs.nix-index.enable = true;

  # fonts.fontDir.enable = true;
  fonts.packages = with pkgs; [
    recursive
    # (nerdfonts.override {fonts = ["JetBrainsMono" "Inconsolata"];})
    nerd-fonts.jetbrains-mono
    nerd-fonts.inconsolata
  ];

  # Set Git commit hash for darwin-version.
  # system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
}
