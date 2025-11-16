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
    ai-tools.enable = true;
  };

  # Programs configuration
  programs = {
    # Enable home-manager
    home-manager.enable = true;

    # Enable nix-index for marshmallow
    nix-index.enable = true;

    # Enable zed editor
    zed-editor.enable = lib.mkForce true;

    # Fish plugins specific to marshmallow
    fish.plugins = [
      {
        name = "tide";
        inherit (pkgs.fishPlugins.tide) src;
      }
    ];

    swayr = {
      enable = false;
      systemd.enable = false;
      settings = {
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
          window_format = "img:{app_icon}:text:{indent}<i>{app_name}</i> — {urgency_start}<b>\"{title}\"</b>{urgency_end} <i>{marks}</i> on workspace {workspace_name} / {output_name}    <span alpha='\"20000\"'>({id})</span>";
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
    };

    waybar = {
      enable = false;
      systemd.enable = false;
    };

    wofi = {
      enable = false;
      settings = {
        allow_images = true;
        insensitive = true;
        allow_markup = true;
        parse-search = true;
      };
    };

    swaylock = {
      enable = true;
    };
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # Wayland configuration
  wayland.windowManager.sway = {
    enable = false;
    systemd.enable = false;
    config = {
      modifier = "Mod4";
      terminal = "kitty";
      menu = "wofi --show drun,run";
      bars = [];
      keybindings = let
        inherit (config.wayland.windowManager.sway.config) modifier;
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
  };

  # Services configuration
  services = {
    swayidle = {
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

    clipmenu = {
      enable = true;
      launcher = "wofi";
    };

    swayosd.enable = true;
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
