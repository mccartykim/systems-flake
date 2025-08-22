# Bartleby - ThinkPad 131e netbook (minimalist i3 setup)
{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Role-based profiles
    ../profiles/base.nix
    ../profiles/laptop.nix
    ../profiles/i3-desktop.nix

    # Nebula mesh network with agenix
    ./nebula.nix
  ];

  # Host identification
  networking.hostName = "bartleby";

  # Intel graphics hardware configuration (older generation)
  hardware.graphics.extraPackages = with pkgs; [
    vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
    vaapiVdpau
    libvdpau-va-gl
  ];

  # Kernel modules for Broadcom WiFi (open-source driver)
  hardware.firmware = [pkgs.linux-firmware];
  boot.initrd.kernelModules = ["kvm-intel"];

  # Swap configuration
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024; # 16GB
    }
  ];

  # User configuration
  users.users.kimb.initialPassword = "pw123";

  # Special service for bartleby
  services.fractalart.enable = true;

  # Override default shell setup
  users.defaultUserShell = pkgs.fish;
  environment.shells = [pkgs.fish];

  # Use rich-evans for DNS
  networking.nameservers = [
    "10.100.0.40" # Rich-evans via Nebula
    "1.1.1.1" # Fallback
  ];

  system.stateVersion = "23.05";
}
