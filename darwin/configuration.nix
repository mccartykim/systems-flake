    {pkgs, self, ...}: {
      # For some reason, nix-darwin needs this stated explicitly
      users.users."kimberly.mccarty".home = "/Users/kimberly.mccarty";
      nixpkgs.config = {
        allowBroken = true;
        allowUnfree = true;
      };
      environment.systemPackages = [
        pkgs.terminal-notifier
        pkgs.cachix
        pkgs.scrcpy
      ];

      # Auto upgrade nix package and the daemon service.
      services.nix-daemon.enable = true;
      nix.package = pkgs.nix;

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";
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

      nix.settings.auto-optimise-store = true;
      nix.useDaemon = true;

      security.pam.enableSudoTouchIdAuth = true;

      # Create /etc/zshrc that loads the nix-darwin environment.
      # programs.zsh.enable = true; # default shell on catalina
      # programs.fish.enable = true;
      programs.nix-index.enable = true;

      # fonts.fontDir.enable = true;
      fonts.packages = with pkgs; [
        recursive
        (nerdfonts.override {fonts = ["JetBrainsMono" "Inconsolata"];})
      ];

      # Set Git commit hash for darwin-version.
      # system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 4;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
    }
