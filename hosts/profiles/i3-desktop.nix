# Minimal desktop environment with i3 window manager
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Services configuration
  services = {
    # X11 and display manager with i3
    xserver = {
      enable = true;
      desktopManager.xterm.enable = false;
      windowManager.i3 = {
        enable = true;
        extraPackages = with pkgs; [
          dmenu
          i3status
          i3lock
        ];
      };
      deviceSection = ''
        Option "DRI" "2"
        Option "TearFree" "true"
      '';
      # Keyboard configuration
      xkb.layout = "us";
    };

    displayManager.defaultSession = "none+i3";

    # Audio - minimal pipewire setup
    pipewire.enable = true;

    # Printing
    printing.enable = true;

    # Minimal touchpad configuration
    libinput = {
      enable = lib.mkForce false;
      touchpad.tapping = false;
    };
  };

  # XDG portal configuration
  xdg.portal.config.common.default = "*";

  # Environment setup for i3
  environment = {
    pathsToLink = ["/libexec"];
    variables = {
      EDITOR = "nvim";
      TERMINAL = "kitty";
    };

    # Basic packages for i3 environment
    systemPackages = with pkgs; [
      firefox
      kitty
      brightnessctl
      linux-firmware
    ];
  };
}
