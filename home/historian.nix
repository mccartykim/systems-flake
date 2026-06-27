# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import other home-manager modules here
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule

    # You can also split up your configuration and import pieces of it here:
    ./default.nix
    ./neovim.nix

    # Import our custom modules
    ./modules/shell-essentials.nix
    ./modules/development.nix
    ./modules/terminal-enhanced.nix
    ./modules/gaming.nix
    ./modules/ai-tools.nix
    ./modules/fish-functions.nix
  ];

  # nixpkgs config inherited from NixOS via useGlobalPkgs = true

  home = {
    username = "kimb";
    homeDirectory = "/home/kimb";

    packages = with pkgs; [
      android-studio
    ];
  };

  # Enable modules
  modules = {
    shell-essentials.enable = true;
    development.enable = true;
    terminal-enhanced = {
      enable = true;
      kitty = true;
      tmux = true;
    };
    gaming.enable = true;
    ai-tools = {
      enable = true;
      claudeZai = true;
      ollamaPi = true;
    };
    fish-functions = {
      enable = true;
      includeJjPrompt = true;
    };
  };

  programs = {
    helix.enable = true;

    # Enable home-manager
    home-manager.enable = true;

    fish.enable = true;
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
