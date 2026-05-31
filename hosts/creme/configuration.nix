# creme - Dell Latitude E6400 ATG writerdeck
# Console-only network appliance — no X/Wayland; syncthing will sync text later.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/laptop.nix
    ../../modules/nebula-node.nix
    ../../modules/peripherals.nix
  ];

  # Doom Emacs as a Nix derivation. Built once (on marshmallow/historian
  # or substituted from the cachix), no per-host doom sync needed.
  nixpkgs.overlays = [inputs.nix-doom-emacs-unstraightened.overlays.default];

  nix.settings.substituters = ["https://doom-emacs-unstraightened.cachix.org/"];
  nix.settings.trusted-public-keys = [
    "doom-emacs-unstraightened.cachix.org-1:O5oOlRPnmQEvVaFyuMTmthCEooHbrg54WgSLR07tmg4="
  ];

  networking.hostName = "creme";
  networking.networkmanager.enable = true;

  # BIOS boot on /dev/sda (no EFI on the E6400)
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = false;
  };

  # Use latest kernel for hardware compat on this old box
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Nebula mesh - reachable from your other personal devices
  kimb.nebula = {
    enable = true;
    openToPersonalDevices = true;
  };

  # Allow kimb to push closures via `nixos-rebuild --target-host`
  nix.settings.trusted-users = ["root" "kimb"];

  # No kmscon. We run X on tty1 with emacs as the only client, so the
  # kernel VT doesn't need the fancy font treatment. tty2-6 stay as
  # plain getty (16 colors, kernel font) for the rare console use.

  # Syncthing for syncing writing across devices.
  # First-run: web UI on http://creme.nebula:8384 to pair folders/devices.
  services.syncthing = {
    enable = true;
    user = "kimb";
    dataDir = "/home/kimb";
    configDir = "/home/kimb/.config/syncthing";
    openDefaultPorts = true;
  };

  # Neovim with vimwiki preloaded; init.lua is yours to write.
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    configure.packages.creme.start = with pkgs.vimPlugins; [vimwiki];
  };

  environment.systemPackages = with pkgs; [
    tmux
    ncmpcpp
    mpc
    alsa-utils
    # mu4e stack — `mu` provides both the binary and emacsPackages.mu4e
    mu
    isync
    gnupg
    # Spellcheck for doom's :checkers spell module
    (hunspellWithDicts [hunspellDicts.en_US])
    # acpi + brightnessctl already provided by laptop profile
    git
    gh
    jujutsu
    helix
  ];

  # gpg-agent for mbsync PassCmd (decrypts ~/.authinfo.gpg).
  programs.gnupg.agent.enable = true;

  # X server with `startx` only — no display manager.
  # i3 is the WM; auto-launches emacsclient + alacritty(tmux) on workspace 1.
  services.xserver = {
    enable = true;
    displayManager.startx.enable = true;
    xkb.layout = "us";
    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [
        dmenu
        i3status
        alacritty
      ];
    };
  };

  # After logging in on tty1, fish auto-execs startx → i3.
  # tty2-6 stay as plain login prompts for the occasional console need.
  # Override by writing your own ~/.xinitrc / ~/.config/i3/config on creme.
  environment.etc."X11/xinit/xinitrc".text = ''
    exec i3
  '';
  programs.fish.loginShellInit = ''
    if test -z "$DISPLAY"; and test (tty) = /dev/tty1
      exec startx
    end
  '';

  # Default i3 config — emacsclient + alacritty(tmux) auto-spawn on
  # workspace 1, vim-style focus keys, BlexMono font. User can override
  # via ~/.config/i3/config (i3 prefers $XDG_CONFIG_HOME).
  environment.etc."i3/config".text = ''
    set $mod Mod4
    font pango:BlexMono Nerd Font Mono 10

    # Autostart on first launch. emacsclient polls until the systemd-managed
    # emacs daemon is up — we DON'T use -a fallback because that'd race-spawn
    # a standalone emacs that steals the server socket from the daemon.
    exec --no-startup-id sh -c 'while ! emacsclient -e t >/dev/null 2>&1; do sleep 1; done; emacsclient -c'
    exec --no-startup-id alacritty --config-file /etc/alacritty.toml -e tmux new-session -A -s main

    # Launchers (daemon is guaranteed up by the time these fire post-login)
    bindsym $mod+Return exec alacritty --config-file /etc/alacritty.toml -e tmux new-session -A -s main
    bindsym $mod+e exec emacsclient -c
    bindsym $mod+d exec dmenu_run -fn 'BlexMono Nerd Font Mono-10'

    # Window management
    bindsym $mod+Shift+q kill
    bindsym $mod+f fullscreen toggle
    bindsym $mod+s split h
    bindsym $mod+v split v

    # Focus (vim keys)
    bindsym $mod+h focus left
    bindsym $mod+j focus down
    bindsym $mod+k focus up
    bindsym $mod+l focus right

    # Move (vim keys + shift)
    bindsym $mod+Shift+h move left
    bindsym $mod+Shift+j move down
    bindsym $mod+Shift+k move up
    bindsym $mod+Shift+l move right

    # Workspaces 1-9
    bindsym $mod+1 workspace number 1
    bindsym $mod+2 workspace number 2
    bindsym $mod+3 workspace number 3
    bindsym $mod+4 workspace number 4
    bindsym $mod+5 workspace number 5
    bindsym $mod+6 workspace number 6
    bindsym $mod+7 workspace number 7
    bindsym $mod+8 workspace number 8
    bindsym $mod+9 workspace number 9
    bindsym $mod+Shift+1 move container to workspace number 1
    bindsym $mod+Shift+2 move container to workspace number 2
    bindsym $mod+Shift+3 move container to workspace number 3
    bindsym $mod+Shift+4 move container to workspace number 4
    bindsym $mod+Shift+5 move container to workspace number 5
    bindsym $mod+Shift+6 move container to workspace number 6
    bindsym $mod+Shift+7 move container to workspace number 7
    bindsym $mod+Shift+8 move container to workspace number 8
    bindsym $mod+Shift+9 move container to workspace number 9

    # Reload / restart
    bindsym $mod+Shift+c reload
    bindsym $mod+Shift+r restart

    # Statusbar: battery + volume + clock + workspaces
    bar {
      status_command i3status
      position top
      font pango:BlexMono Nerd Font Mono 9
    }
  '';

  # Alacritty theme — Nord palette, muted dark for less eye strain than
  # the default white-on-black. Alacritty doesn't read /etc/xdg, so we
  # have to point each i3 launcher at this with --config-file.
  environment.etc."alacritty.toml".text = ''
    [font]
    normal = { family = "BlexMono Nerd Font Mono", style = "Regular" }
    size = 11.0

    [window]
    padding = { x = 4, y = 4 }

    [colors.primary]
    background = "#2e3440"
    foreground = "#d8dee9"

    [colors.normal]
    black   = "#3b4252"
    red     = "#bf616a"
    green   = "#a3be8c"
    yellow  = "#ebcb8b"
    blue    = "#81a1c1"
    magenta = "#b48ead"
    cyan    = "#88c0d0"
    white   = "#e5e9f0"

    [colors.bright]
    black   = "#4c566a"
    red     = "#bf616a"
    green   = "#a3be8c"
    yellow  = "#ebcb8b"
    blue    = "#81a1c1"
    magenta = "#b48ead"
    cyan    = "#8fbcbb"
    white   = "#eceff4"
  '';

  # i3status config with battery / volume / clock
  environment.etc."i3status.conf".text = ''
    general {
      colors = true
      interval = 5
    }

    order += "battery 0"
    order += "volume master"
    order += "tztime local"

    battery 0 {
      format = "%status %percentage %remaining"
      format_down = ""
      path = "/sys/class/power_supply/BAT%d/uevent"
      low_threshold = 10
    }

    volume master {
      format = "♪ %volume"
      format_muted = "♪ muted"
      device = "default"
      mixer = "Master"
      mixer_idx = 0
    }

    tztime local {
      format = "%Y-%m-%d %H:%M"
    }
  '';

  # Emacs daemon (services.emacs creates user systemd unit, fires on login).
  # Uses the nix-doom-emacs-unstraightened wrapper — doomDir is read at
  # build time from the in-flake hosts/creme/doom.d/, so M-x customize Save
  # silently fails (the dir is in /nix/store, read-only). Runtime state
  # lives in $XDG_DATA_HOME/nix-doom (default), which IS writable.
  #
  # startWithGraphical=false because we use bare startx (no display manager);
  # graphical-session.target never fires under PAM, so it'd never start the
  # daemon. With default.target, the daemon starts at user login regardless
  # of X — emacsclient -c passes DISPLAY at request time so GUI frames still
  # work fine when called from inside i3.
  services.emacs = {
    enable = true;
    startWithGraphical = false;
    package = pkgs.emacsWithDoom {
      doomDir = ./doom.d;
      doomLocalDir = "~/.local/share/nix-doom";
      extraPackages = epkgs: [epkgs.treesit-grammars.with-all-grammars];
    };
  };

  # Fonts. Blex Mono Nerd Font as primary; Google monochrome emoji noto
  # so emoji render cleanly without dragging in colored fallback bitmaps.
  fonts.packages = with pkgs; [
    nerd-fonts.blex-mono
    noto-fonts-monochrome-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = ["BlexMono Nerd Font Mono"];
    emoji = ["Noto Emoji"];
  };

  # Sound — pipewire SYSTEM-WIDE so the system mpd service can reach it.
  # Per-user pipewire would be cleaner on a multi-user desktop, but creme
  # is a single-user writerdeck and the system mpd needs an audio socket
  # that doesn't depend on a user session. Discouraged-but-supported per
  # the NixOS pipewire.nix docs. kimb needs to be in `pipewire` group.
  services.pipewire = {
    enable = true;
    systemWide = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # MPD runs as user kimb so the music dir can live in $HOME (where
  # syncthing drops files from shared_music / compressed_music).
  # Change musicDirectory after syncthing is set up if the path differs.
  services.mpd = {
    enable = true;
    user = "kimb";
    musicDirectory = "/home/kimb/Music";
    dataDir = "/home/kimb/.local/share/mpd";
    network.listenAddress = "127.0.0.1";
    # Explicit pulse output → routed through systemWide pipewire-pulse.
    # Without this mpd auto-detects JACK first (binary has libjack linked)
    # and fails to connect to a non-existent JACK server.
    settings = {
      audio_output = [
        {
          type = "pulse";
          name = "pipewire (pulse)";
        }
      ];
    };
  };

  # MPD as a user-owned service needs its dirs to exist; systemd won't
  # create paths under /home automatically.
  systemd.tmpfiles.rules = [
    "d /home/kimb/Music                 0755 kimb users -"
    "d /home/kimb/.local                0755 kimb users -"
    "d /home/kimb/.local/share          0755 kimb users -"
    "d /home/kimb/.local/share/mpd      0755 kimb users -"
    "d /home/kimb/.local/share/mpd/playlists 0755 kimb users -"
  ];

  # Media + brightness keys via actkbd. Works in TTY and X — no WM needed.
  # actkbd runs as root, so brightnessctl + amixer + mpc all work without
  # user-session perms. Pipewire respects ALSA Master, so amixer keys do
  # what you'd expect.
  services.actkbd = {
    enable = true;
    bindings = [
      # Brightness (Fn keys → /sys/class/backlight)
      {keys = [224]; events = ["key"]; command = "${pkgs.brightnessctl}/bin/brightnessctl set 10%-";}
      {keys = [225]; events = ["key"]; command = "${pkgs.brightnessctl}/bin/brightnessctl set +10%";}
      # Volume (ALSA Master — pipewire honors it)
      {keys = [113]; events = ["key"]; command = "${pkgs.alsa-utils}/bin/amixer -q set Master toggle";}
      {keys = [114]; events = ["key"]; command = "${pkgs.alsa-utils}/bin/amixer -q set Master 5%-";}
      {keys = [115]; events = ["key"]; command = "${pkgs.alsa-utils}/bin/amixer -q set Master 5%+";}
      # Media (mpc → mpd on localhost:6600)
      {keys = [164]; events = ["key"]; command = "${pkgs.mpc}/bin/mpc toggle";}
      {keys = [163]; events = ["key"]; command = "${pkgs.mpc}/bin/mpc next";}
      {keys = [165]; events = ["key"]; command = "${pkgs.mpc}/bin/mpc prev";}
    ];
  };

  # tty: lets `startx` open /dev/tty0 without setuid Xorg.
  # NOTE: start X from a non-kmscon VT (Ctrl+Alt+F2 → login → `startx`),
  # otherwise kmscon@tty1 holds the DRM device.
  users.users.kimb.extraGroups = ["audio" "video" "tty" "pipewire"];

  system.stateVersion = "25.11";
}
