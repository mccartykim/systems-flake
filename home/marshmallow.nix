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
  ];

  # Enable modules
  modules.shell-essentials.enable = true;
  modules.development.enable = true;
  modules.terminal-enhanced = {
    enable = true;
    kitty = true;
  };
  modules.gaming = {
    enable = true;
    steam = true;
  };
  modules.ai-tools.enable = true;

  # Fish plugins specific to marshmallow
  programs.fish.plugins = [
    {
      name = "tide";
      src = pkgs.fishPlugins.tide.src;
    }
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      allowUnfree = true;
    };
  };

  home = {
    username = "kimb";
    homeDirectory = "/home/kimb";
  };

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  # Marshmallow-specific packages
  home.packages = with pkgs; [
    nerd-fonts.symbols-only
    noto-fonts-monochrome-emoji
    poetry
  ];

  # Enable home-manager
  programs.home-manager.enable = true;

  # Enable nix-index for marshmallow
  programs.nix-index.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  wayland.windowManager.sway.enable = false;
  wayland.windowManager.sway.config.modifier = "Mod4";
  wayland.windowManager.sway.systemd.enable = false;
  wayland.windowManager.sway.config.terminal = "kitty";
  wayland.windowManager.sway.config = {
    menu = "wofi --show drun,run";
    bars = [];
    keybindings = let
      modifier = config.wayland.windowManager.sway.config.modifier;
    in
      lib.mkOptionDefault {
        "Mod1+Tab" = "exec ${pkgs.swayr}/bin/swayr switch-to-urgent-or-lru-window";
        #
        #
        "${modifier}+Shift+f" = "floating toggle";
        "${modifier}+Shift+w" = "focus mode_toggle";
        "${modifier}+c" = "exec ${pkgs.swayr}/bin/swayr execute-swaymsg-command";
        "${modifier}+Shift+c" = "exec ${pkgs.swayr}/bin/swayr execute-swayr-command";
        "${modifier}+Tab" = "exec ${pkgs.swayr}/bin/swayr switch-window";
        "${modifier}+Shift+Tab" = "exec ${pkgs.swayr}/bin/swayr switch-workspace-or-window";
        "XF86AudioRaiseVolume" = "exec ${pkgs.pamixer}/bin/pamixer -i 5";
        "XF86AudioLowerVolume" = "exec ${pkgs.pamixer}/bin/pamixer -d 5";
        "XF86AudioMute" = "exec ${pkgs.pamixer}/bin/pamixer --toggle-mute";
      };
  };
  programs.swayr.enable = false;
  programs.swayr.systemd.enable = false;
  programs.swayr.settings = {
    menu = {
      executable = "${pkgs.wofi}/bin/wofi";
      args = [
        "--show=dmenu"
        "--allow-markup"
        "--allow-images"
        "--insensitive"
        "--cache-file=/dev/null"
        "--parse-search"
        "--height=40%"
        "--prompt={prompt}"
      ];
    };

    format = {
      output_format = "{indent}<b>Output {name}</b> <span alpha='\"20000\"'>({id})</span>";
      workspace_format = "{indent}<b>Workspace {name} [{layout}]</b> on output {output_name}    <span alpha='\"20000\"'>({id})</span>";
      container_format = "{indent}<b>Container [{layout}]</b> <i>{marks}</i> on workspace {workspace_name}    <span alpha='\"20000\"'>({id})</span>";
      window_format = "img:{app_icon}:text:{indent}<i>{app_name}</i> — {urgency_start}<b>“{title}”</b>{urgency_end} <i>{marks}</i> on workspace {workspace_name} / {output_name}    <span alpha='\"20000\"'>({id})</span>";
      indent = "    ";
      urgency_start = "<span background='\"darkred\"' foreground='\"yellow\"'>";
      urgency_end = "</span>";
      html_escape = true;
    };

    layout = {
      auto_tile = false;
      auto_tile_min_window_width_per_output_width = [
        [800 400]
        [1024 500]
        [1280 600]
        [1400 680]
        [1440 700]
        [1600 780]
        [1680 780]
        [1920 920]
        [2048 980]
        [2560 1000]
        [3440 1200]
        [3840 1280]
        [4096 1400]
        [4480 1600]
        [7680 2400]
      ];
    };

    focus = {
      lockin_delay = 750;
    };

    misc = {
      seq_inhibit = false;
    };
  };
  programs.waybar.enable = false;
  programs.waybar.systemd.enable = false;
  programs.wofi = {
    enable = false;
    settings = {
      allow_images = true;
      insensitive = true;
      allow_markup = true;
      parse-search = true;
    };
  };

  services.swayidle = {
    enable = false;
    events = [
      {
        event = "before-sleep";
        command = "${pkgs.swaylock}/bin/swaylock -fF";
      }
    ];
    timeouts = [
      {
        timeout = 60 * 5;
        command = "${pkgs.swaylock}/bin/swaylock -fF";
      }
      {
        timeout = 60 * 20;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
  };
  programs.swaylock = {
    enable = true;
  };
  services.clipmenu = {
    enable = true;
    launcher = "wofi";
  };
  services.swayosd.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
