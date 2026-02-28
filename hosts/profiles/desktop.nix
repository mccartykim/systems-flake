# Desktop environment configuration for KDE Plasma systems
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Services configuration
  services = {
    # X11 and display manager
    xserver = {
      enable = true;
      # Keyboard configuration
      xkb = {
        layout = "us";
        variant = "";
      };
    };
    displayManager.sddm.enable = true;
    desktopManager.plasma6.enable = true;

    # Audio stack - PipeWire
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    # Printing
    printing.enable = true;
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # Additional desktop services
    gvfs.enable = true;
    udisks2.enable = true;
    devmon.enable = true;

    # Flatpak support
    flatpak.enable = true;

    # Key remapping daemon (works on X11 and Wayland)
    keyd = {
      enable = true;
      keyboards = {
        # Realforce JIS keyboard - remap Asian character keys
        # Find ID with: keyd -m (or lsusb | grep -i topre)
        realforce = {
          ids = ["0853:0200"]; # Topre RealForce Compact
          settings = {
            main = {
              # Muhenkan (left of space) → Backspace
              muhenkan = "backspace";
              # Henkan (right of space) → Right Ctrl
              henkan = "rightcontrol";
              # Katakanahiragana (further right) → Hyper (all mods when held)
              katakanahiragana = "layer(hyper)";
            };
            # Hyper layer: any key pressed while held gets all modifiers
            "hyper:C-S-M-A" = {};
          };
        };
      };
    };
  };

  # Security configuration
  security.rtkit.enable = true;

  # GPG agent - pinentry-all auto-selects Qt/curses/tty based on environment
  # This works for both KDE desktop and SSH sessions
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-all;
  };

  # Hardware configuration
  hardware = {
    # Bluetooth
    bluetooth.enable = true;

    # Graphics
    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
  xdg.portal.enable = true;

  # Firefox with KDE file picker integration and hardware acceleration
  programs.firefox = {
    enable = true;
    preferences = {
      # Use KDE file picker via xdg-desktop-portal
      "widget.use-xdg-desktop-portal.file-picker" = 1;
      # Use KDE for opening links/files
      "widget.use-xdg-desktop-portal.mime-handler" = 1;
      # Hardware video decoding (VA-API)
      "media.ffmpeg.vaapi.enabled" = true;
      "media.hardware-video-decoding.enabled" = true;
      # GPU-accelerated rendering (WebRender)
      "gfx.webrender.all" = true;
    };
  };


  # Add desktop-specific packages
  environment.systemPackages = with pkgs; [
    vlc
    pinentry-curses
    pinentry-qt # KDE/Qt GUI for gpg passphrase entry
  ];

  # Font configuration
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
  ];
}
