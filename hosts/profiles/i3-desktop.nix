# Minimal desktop environment with i3 window manager
{
  config,
  lib,
  pkgs,
  ...
}: {
  # X11 and display manager with i3
  services.xserver = {
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
  };

  services.displayManager.defaultSession = "none+i3";

  # Keyboard configuration
  services.xserver.xkb.layout = "us";

  # Audio - minimal pipewire setup
  services.pipewire.enable = true;

  # Printing
  services.printing.enable = true;

  # Minimal touchpad configuration
  services.libinput = {
    enable = lib.mkForce false;
    touchpad.tapping = false;
  };

  # XDG portal configuration
  xdg.portal.config.common.default = "*";

  # Environment setup for i3
  environment.pathsToLink = ["/libexec"];
  environment.variables = {
    EDITOR = "nvim";
    TERMINAL = "kitty";
  };

  # Basic packages for i3 environment
  environment.systemPackages = with pkgs; [
    firefox
    kitty
    brightnessctl
    linux-firmware
  ];
}
