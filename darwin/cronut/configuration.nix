{pkgs, ...}: {
  # For some reason, nix-darwin needs this stated explicitly
  users.users."kim".home = "/Users/kim";
  nixpkgs = {
    config = {
      allowBroken = true;
      allowUnfree = true;
    };
    # flake.setNixPath = true;
    flake.setFlakeRegistry = true;
    hostPlatform = "x86_64-darwin";
  };
  environment.systemPackages = [
    pkgs.terminal-notifier
    pkgs.cachix
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
      trusted-users = [
        "kim"
      ];
      substituters = [
        "https://cache.garnix.io"
      ];
      trusted-public-keys = [
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
    };
    optimise.automatic = true;
  };

  programs.fish.enable = true;

  system = {
    primaryUser = "kim";
    defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;
    stateVersion = 5;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
  };

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
}
