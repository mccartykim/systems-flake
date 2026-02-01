# Home configuration for donut (Steam Deck)
# Minimal config focused on gaming - most interaction is through Gaming Mode
{pkgs, ...}: {
  imports = [
    ./default.nix
    ./modules/shell-essentials.nix
    ./modules/terminal-enhanced.nix
    ./modules/gaming.nix
  ];

  home = {
    username = "kimb";
    homeDirectory = "/home/kimb";

    # Packages for desktop mode
    packages = with pkgs; [
      # Web browsing
      firefox

      # Terminal
      ghostty

      # System monitoring
      btop

      # File management
      kdePackages.dolphin

      # Media
      vlc

      # Gaming utilities (for desktop mode)
      protonup-qt # Manage Proton versions
      ludusavi # Game save backup
    ];
  };

  # Enable modules
  modules = {
    shell-essentials.enable = true;
    terminal-enhanced = {
      enable = true;
      kitty = true;
    };
    gaming = {
      enable = true;
      steam = true;
    };
  };

  # Fish shell
  programs.fish.enable = true;

  # Shell history sync
  programs.atuin.enable = true;

  # Enable home-manager
  programs.home-manager.enable = true;

  home.stateVersion = "24.11";
}
