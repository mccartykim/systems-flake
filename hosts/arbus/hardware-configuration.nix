# Hardware configuration for Raspberry Pi Gen 1
# This is a minimal placeholder - adjust based on your actual hardware
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-armv6l-multiplatform.nix")
  ];

  # Raspberry Pi Gen 1 uses ARMv6
  nixpkgs.hostPlatform = "armv6l-linux";

  # Auto-expand root partition to fill SD card on first boot
  boot.growPartition = true;

  # Enable basic firmware
  hardware.enableRedistributableFirmware = true;

  # Filesystem configuration
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # Swap configuration (optional, adjust size as needed)
  swapDevices = [];

  # Enable GPU firmware
  hardware.raspberry-pi."1" = {
    fkms-3d.enable = true;
  };
}
