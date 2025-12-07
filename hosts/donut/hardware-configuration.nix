# Steam Deck hardware configuration
# Jovian NixOS handles all Steam Deck-specific hardware:
#   - Graphics (AMD Van Gogh APU, RADV, 32-bit)
#   - Kernel (neptune kernel with Steam Deck patches)
#   - Firmware, fan control, gyro, sound, etc.
#
# This file only defines filesystem layout and basic boot modules.
{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Basic initrd modules for mounting disks
  boot.initrd.availableKernelModules = [
    "nvme" # Internal NVMe
    "xhci_pci" # USB
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sdhci_pci" # SD card
  ];

  # Filesystem layout (created by installer)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
