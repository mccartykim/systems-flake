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
    # Marshmallow-specific packages
    packages = with pkgs; [
      nerd-fonts.symbols-only
      noto-fonts-monochrome-emoji
      poetry
      zettlr
      claude-code
      # Erlang/Elixir/Gleam development
      erlang
      elixir
      gleam
      rebar3
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
    };
    gaming = {
      enable = true;
      steam = true;
    };
    ai-tools = {
      enable = true;
      claudeZai = true;
      ollamaPi = true;
    };
    fish-functions = {
      enable = true;
      # Marshmallow uses tide for its prompt; no need for the jj prompt override
      includeJjPrompt = false;
    };
  };

  # GPG agent - Qt pinentry for KDE integration
  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-qt;
    defaultCacheTtl = 7200; # Cache passphrase for 2 hours
    maxCacheTtl = 86400; # Max cache 24 hours
  };

  # Programs configuration
  programs = {
    # Enable home-manager
    home-manager.enable = true;

    # GPG with home-manager
    gpg.enable = true;

    # Enable nix-index for marshmallow
    nix-index.enable = true;

    # Enable zed editor
    zed-editor.enable = lib.mkForce true;

    # Fish configuration specific to marshmallow
    fish = {
      plugins = [
        {
          name = "tide";
          inherit (pkgs.fishPlugins.tide) src;
        }
      ];
    };

    swaylock = {
      enable = true;
    };
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # Services configuration
  services = {
    clipmenu = {
      enable = true;
      launcher = "wofi";
    };

    swayosd.enable = true;
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}