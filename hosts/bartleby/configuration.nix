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

    # Nebula mesh network (consolidated module)
    ../../modules/nebula-node.nix

    # Restic backups to Backblaze B2
    ../../modules/restic-backup.nix
  ];

  # Restic backups
  kimb.restic.enable = true;
  kimb.restic.extraExclude = [
    "/home/kimb/.android"
    "/home/kimb/.gradle"
  ];

  # Nebula configuration
  kimb.nebula = {
    enable = true;
    openToPersonalDevices = true;
  };

  # Host identification
  networking.hostName = "bartleby";

  # Intel graphics hardware configuration (older generation)
  hardware.graphics.extraPackages = with pkgs; [
    intel-vaapi-driver # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
    libva-vdpau-driver
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

  # Use maitred router for DNS
  networking.nameservers = let
    registry = import ../nebula-registry.nix;
  in [
    registry.nodes.maitred.ip # maitred router via Nebula
    "1.1.1.1" # Fallback
  ];

  # Printing via maitred (IPP Everywhere - server handles rendering)
  hardware.printers = {
    ensurePrinters = [
      {
        name = "Brother-HL-L2400D";
        description = "Brother HL-L2400D Laser Printer";
        location = "Living Room";
        deviceUri = "ipp://maitred.nebula:631/printers/Brother-HL-L2400D";
        model = "everywhere";
      }
    ];
    ensureDefaultPrinter = "Brother-HL-L2400D";
  };

  system.stateVersion = "23.05";
}
