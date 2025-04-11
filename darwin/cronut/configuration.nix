{pkgs, ...}: {
  # For some reason, nix-darwin needs this stated explicitly
  users.users."kim".home = "/Users/kim";
  nixpkgs.config = {
    allowBroken = true;
    allowUnfree = true;
  };
  # nixpkgs.flake.setNixPath = true;
  nixpkgs.flake.setFlakeRegistry = true;
  environment.systemPackages = [
    pkgs.terminal-notifier
    pkgs.cachix
  ];
  nix.nixPath = pkgs.lib.mkForce [
    {
      darwin-config = builtins.concatStringsSep ":" [
        "$HOME/.nixpkgs/darwin-configuration.nix"
        "$HOME/.nix-defexpr/channels"
      ];
    }
  ];

  programs.fish.enable = true;
  system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";
  nix.settings.trusted-users=[
    "kim"
  ];
  nix.settings.substituters = [
    "https://cache.nixos.org/"
    "https://nix-community.cachix.org/"
    "https://cache.garnix.io"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];

  nix.optimise.automatic = true;

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
  nixpkgs.hostPlatform = "x86_64-darwin";
}
