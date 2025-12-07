# Steam Deck hardware configuration
# This is a template - actual hardware config should be regenerated on first boot
# with: nixos-generate-config --show-hardware-config
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Steam Deck uses AMD Van Gogh APU
  boot = {
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "usbhid"
        "usb_storage"
        "sd_mod"
        "sdhci_pci" # SD card support
      ];
      kernelModules = ["amdgpu"];
    };

    kernelModules = ["kvm-amd"];

    # Jovian handles kernel selection for Steam Deck
    # loader configured in base.nix (systemd-boot)
  };

  # Steam Deck internal NVMe - single partition layout
  # The installer will set this up, but define expected layout
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  # Hardware configuration
  hardware = {
    # AMD GPU (Van Gogh APU)
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        amdvlk
        rocmPackages.clr
        rocmPackages.clr.icd
      ];
      extraPackages32 = with pkgs.pkgsi686Linux; [
        amdvlk
      ];
    };

    # CPU microcode
    cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    # Enable all firmware
    enableRedistributableFirmware = true;
    enableAllFirmware = true;
  };

  # Steam Deck has a fixed platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
