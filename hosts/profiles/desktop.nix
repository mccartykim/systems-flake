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

  # Add desktop-specific packages
  environment.systemPackages = with pkgs; [
    firefox
    vlc
    pinentry-curses
    pinentry-qt  # KDE/Qt GUI for gpg passphrase entry
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
