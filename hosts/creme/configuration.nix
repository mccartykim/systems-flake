# creme - Dell Latitude E6400 ATG writerdeck
# i3 + emacs writerdeck; libreboot 26.01rev1 firmware. Syncthing for text sync.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./disk-encryption.nix
    ../profiles/base.nix
    ../profiles/laptop.nix
    ../../modules/nebula-node.nix
    ../../modules/peripherals.nix
    # Stylix derives a base16 colorscheme from the PDX-carpet wallpaper
    # and applies it across the desktop (gtk, qt, terminals, vim, etc.).
    inputs.stylix.nixosModules.stylix
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

  # WiFi: per-AP randomization. Mostly meaningful when the writerdeck
  # leaves the house. (Ethernet MAC is handled by libreboot's GbE region —
  # set at flash time with nvmutil to a locally-administered random value.)
  networking.networkmanager.wifi.macAddress = "random";
  networking.networkmanager.wifi.scanRandMacAddress = true;

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

  # Plymouth boot splash. Hides the kernel/systemd-boot scrollback wall
  # behind a clean spinner from kernel handoff onward. Plymouth needs the
  # systemd-based initrd to coordinate with the spinner; libreboot's
  # SeaBIOS+GRUB chainload still scrolls a bit before kernel takeover,
  # but everything from there to login is quiet.
  boot.plymouth.enable = true;
  boot.initrd.systemd.enable = true;
  boot.kernelParams = [ "quiet" "splash" "loglevel=3" "rd.systemd.show_status=auto" "rd.udev.log_level=3" "resume_offset=56424448" ];
  # Hibernate resume from swapfile on /dev/sda2 (ext4).
  # resume_offset is the physical block offset from `filefrag -e /swapfile`.
  boot.resumeDevice = "/dev/sda2";
  boot.consoleLogLevel = 3;

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
    # uxterm — Unicode wrapper around xterm. TrueType fonts via Xft (no
    # patching needed), scrollback, 256-color, proper unicode, and X
    # resource theming. Replaces st as the primary terminal on creme
    # because st requires patch-and-rebuild for any config change while
    # xterm reads X resources at startup.
    xterm
  ];

  # ─── Stylix: derive desktop colors from the PDX-carpet wallpaper ────
  #
  # The wallpaper itself is built from the SVG via pkgs/pdx-wallpaper
  # (rsvg-convert → PNG). `scale` controls tile size; the SVG is 490×490
  # at scale=1 and tiles seamlessly, so bumping scale just makes each
  # tile take up more screen real estate. On a 1440×900 panel (E6400
  # native) scale=1 fits roughly 3×2 visible tiles — the classic PDX
  # carpet density.
  stylix = {
    enable = true;
    # scale = 1.0/3.0 → ~163px tile, so ~9×6 tiles fit on a 1440×900 panel.
    # Bigger pattern density than scale=1; matches the "carpet underfoot"
    # feel of the original PDX terminal carpet a bit closer.
    image = pkgs.callPackage ../../pkgs/pdx-wallpaper { scale = 1.0 / 6.0; };
    # Wallpaper is a tiled pattern, not a single-frame image.
    imageScalingMode = "tile";
    # Hand-tuned base16 scheme derived from the PDX-carpet SVG's actual
    # colors, designed for HIGH contrast on the E6400's TN panel
    # (~60% sRGB coverage, washes saturated colors out at low brightness):
    #
    #   #6FD6A8 → base0B (strings / success / "go" green) — the carpet's
    #              mint background, kept saturated so it pops on near-black
    #   #544A93 → base02 (selection) — the deep purple X-shapes, used as
    #              UI chrome accent; original is too dark for foreground text
    #   #8279D2 → base0D (functions / "thinking" blue-purple) — lifted
    #              variant of the deep purple, readable against base00
    #   #FB2C42 → base08 (variables / errors) — the carpet's red squares
    #   #F7BEDF → base0F (special / quotes) — the pale pink diagonals;
    #              works as a soft accent, not for primary text
    #
    # Background is pure-black-leaning charcoal (#08080c) instead of the
    # carpet's mint, because the carpet IS the wallpaper — the desktop
    # itself shouldn't compete. Foreground is near-white (#f4f4f8) for
    # maximum legibility.
    base16Scheme = {
      base00 = "08080c"; # background
      base01 = "16161e"; # status bar / line highlight bg
      base02 = "2d2640"; # selection — PDX deep purple tinted
      base03 = "5a5a72"; # comments — readable grey-purple
      base04 = "b0b0c0"; # status bar fg
      base05 = "f4f4f8"; # default foreground — high contrast
      base06 = "fafafc"; # light fg
      base07 = "ffffff"; # extreme highlight
      base08 = "fb2c42"; # red (PDX scarlet) — vars, errors
      base09 = "ff8a5c"; # orange — derived from red toward warmth
      base0A = "ffd966"; # yellow — types, search hits
      base0B = "6fd6a8"; # green (PDX mint) — strings, success
      base0C = "a0e8d0"; # cyan — lighter mint
      base0D = "8279d2"; # blue (PDX medium purple) — functions
      base0E = "a899e8"; # magenta-purple — keywords
      base0F = "f7bedf"; # pink (PDX pale pink) — special
    };
    polarity = "dark";
    # Keep BlexMono Nerd Font as the monospace choice for the i3 bar
    # and xterm rather than letting stylix pick a different one.
    # Pin emoji to the monochrome Noto sibling — Noto Color Emoji's
    # blobby SVG glyphs look terrible in cell terminals.
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.blex-mono;
        name = "BlexMono Nerd Font Mono";
      };
      emoji = {
        package = pkgs.noto-fonts;
        name = "Noto Emoji";
      };
    };
    # stylix's kmscon target uses the removed services.kmscon.fonts and
    # services.kmscon.extraConfig options (upstream bug). creme doesn't
    # use kmscon anyway (see comment above), so just disable the target.
    targets.kmscon.enable = false;
  };

  # gpg-agent for mbsync PassCmd (decrypts ~/.authinfo.gpg).
  programs.gnupg.agent.enable = true;

  # Lid switch → suspend-then-hibernate. S3 first, then hibernates
  # after HibernateDelaySec. Libreboot on the E6400 doesn't reliably
  # deliver ACPI GPEs for lid state changes, so logind may never see
  # the event. We set all three lid handlers explicitly and add a
  # polling watchdog as a fallback.
  services.logind = {
    lidSwitch = "suspend-then-hibernate";
    lidSwitchExternalPower = "suspend-then-hibernate";
    lidSwitchDocked = "suspend-then-hibernate";
  };
  # 4GB swapfile for hibernate. Created manually with fallocate;
  # NixOS runs mkswap + swapon on activation.
  swapDevices = [{device = "/swapfile";}];
  systemd.services.lid-watchdog = {
    description = "Poll lid state and suspend on close (Libreboot fallback)";
    wantedBy = ["multi-user.target"];
    path = [pkgs.gnugrep];
    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "lid-watchdog" ''
        while true; do
          if grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
            systemctl suspend-then-hibernate
            sleep 30
          fi
          sleep 5
        done
      '';
      Restart = "always";
      RestartSec = 10;
    };
  };

  # Minimal X compositor. xrender backend has no GL dependency and stays
  # cheap on the E6400's GMA 4500MHD. No shadow, no fade, no vsync —
  # those are real perf knobs on old hw and we don't need any of them
  # here, just compositing for transparency.
  services.picom = {
    enable = true;
    backend = "xrender";
    vSync = false;
    fade = false;
    shadow = false;
    settings = {
      detect-rounded-corners = true;
      detect-client-opacity = true;
      use-ewmh-active-win = true;
      unredir-if-possible = true;  # disable comp when a fullscreen app
                                   # is up (e.g. mpv) — saves CPU
    };
  };

  # X server with `startx` only — no display manager.
  # i3 is the WM; auto-launches emacsclient + xterm(tmux) on workspace 1.
  services.xserver = {
    enable = true;
    displayManager.startx.enable = true;
    xkb.layout = "us";
    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [
        dmenu
        i3status
      ];
    };
  };

  # After logging in on tty1, fish auto-execs startx → i3.
  # tty2-6 stay as plain login prompts for the occasional console need.
  # Override by writing your own ~/.xinitrc on creme.
  #
  # We paint the wallpaper before i3 starts (with `&` so it doesn't block).
  # Stylix would normally do this via a display manager hook, but creme runs
  # startx so we wire feh directly. `config.stylix.image` resolves to the
  # PDX-carpet PNG derivation defined in the stylix block below.
  #
  # picom is started here (not via its systemd user service) because creme
  # uses bare startx — graphical-session.target never activates, so the
  # service stays dead.  xrender backend is light enough for the E6400.
  environment.etc."X11/xinit/xinitrc".text = ''
    ${pkgs.xorg.xrdb}/bin/xrdb -merge /etc/X11/Xresources/creme
    ${pkgs.feh}/bin/feh --no-fehbg --bg-tile ${config.stylix.image} &
    ${pkgs.picom}/bin/picom --backend xrender -b
    exec i3
  '';

  # Auto-startx on tty1 login. tty2-6 stay as plain getty.
  programs.fish.loginShellInit = ''
    if test -z "$DISPLAY"; and test (tty) = /dev/tty1
      exec startx
    end
  '';

  # Default i3 config — emacsclient + xterm(tmux) auto-spawn on
  # workspace 1, vim-style focus keys, BlexMono font.
  # NOTE: delete ~/.config/i3/config on creme if it exists (wizard-generated
  # shadow), otherwise this /etc/i3/config is ignored.
  environment.etc."i3/config".text = ''
    set $mod Mod4
    font pango:BlexMono Nerd Font Mono 10

    # Autostart on first launch. emacsclient polls until the systemd-managed
    # emacs daemon is up — we DON'T use -a fallback because that'd race-spawn
    # a standalone emacs that steals the server socket from the daemon.
    exec --no-startup-id sh -c 'while ! emacsclient -e t >/dev/null 2>&1; do sleep 1; done; emacsclient -c'

    # Launchers
    bindsym $mod+Return exec uxterm -e tmux new-session -A -s main
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

    # Brightness — libreboot drops Dell EC SCI, so XF86 keysyms may not
    # fire. actkbd handles the Fn keys at the kernel level; these are
    # i3-level fallbacks.
    bindsym $mod+F8 exec --no-startup-id ${pkgs.brightnessctl}/bin/brightnessctl set 10%-
    bindsym $mod+F9 exec --no-startup-id ${pkgs.brightnessctl}/bin/brightnessctl set +10%
    bindsym $mod+Ctrl+Up exec --no-startup-id ${pkgs.brightnessctl}/bin/brightnessctl set +10%
    bindsym $mod+Ctrl+Down exec --no-startup-id ${pkgs.brightnessctl}/bin/brightnessctl set 10%-

    # Statusbar: battery + volume + clock + workspaces
    bar {
      status_command i3status -c /etc/i3status.conf
      position top
      font pango:BlexMono Nerd Font Mono 9
    }
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

  # Doom startup can be slow on this machine (treesit grammars, many packages).
  # The default TimeoutStartSec of 90s is too aggressive — emacs with notify
  # type needs to finish loading before signaling READY=1, which can take 2-3
  # minutes on cold start. The activation failure on 2026-06-04 was caused by
  # this timeout firing repeatedly during nixos-rebuild switch.
  systemd.user.services.emacs.serviceConfig.TimeoutStartSec = "300";

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

  # X resources for uxterm. Stylix has no NixOS-level xresources module,
  # so we mirror the PDX-carpet palette and BlexMono font here. The xinitrc
  # merges this file with xrdb before i3 starts, so all X apps (uxterm,
  # dmenu, etc.) pick up the theme.  uxterm uses the UXTerm resource class
  # (not XTerm), so we prefix with UXTerm* to match.
  environment.etc."X11/Xresources/creme".text = with config.stylix;
    let
      c = base16Scheme;
    in ''
      ! ── Font ──
      UXTerm*faceName: ${fonts.monospace.name}
      UXTerm*faceSize: ${toString fonts.sizes.terminal}
      UXTerm*renderFont: true
      UXTerm*termName: xterm-256color
      UXTerm*scrollBar: false
      UXTerm*saveLines: 10000
      UXTerm*allowBoldFonts: true
      UXTerm*boldMode: false

      ! ── PDX-carpet base16 palette (mirrors stylix/xresources/hm.nix) ──
      UXTerm*foreground: #${c.base05}
      UXTerm*background: #${c.base00}
      UXTerm*cursorColor: #${c.base05}
      UXTerm*color0:  #${c.base00}
      UXTerm*color1:  #${c.base08}
      UXTerm*color2:  #${c.base0B}
      UXTerm*color3:  #${c.base0A}
      UXTerm*color4:  #${c.base0D}
      UXTerm*color5:  #${c.base0E}
      UXTerm*color6:  #${c.base0C}
      UXTerm*color7:  #${c.base05}
      UXTerm*color8:  #${c.base02}
      UXTerm*color9:  #${c.base08}
      UXTerm*color10: #${c.base0B}
      UXTerm*color11: #${c.base0A}
      UXTerm*color12: #${c.base0D}
      UXTerm*color13: #${c.base0E}
      UXTerm*color14: #${c.base0C}
      UXTerm*color15: #${c.base07}
      ! ── Extended 22-color palette (base09–base06, per stylix) ──
      UXTerm*color16: #${c.base09}
      UXTerm*color17: #${c.base0F}
      UXTerm*color18: #${c.base01}
      UXTerm*color19: #${c.base02}
      UXTerm*color20: #${c.base04}
      UXTerm*color21: #${c.base06}
    '';

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
