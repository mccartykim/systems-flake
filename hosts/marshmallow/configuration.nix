# Marshmallow - ThinkPad T490 (Intel graphics, gaming laptop)
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Role-based profiles
    ../profiles/base.nix
    ../profiles/desktop.nix
    ../profiles/laptop.nix
    ../profiles/gaming.nix

    # Nebula mesh network (consolidated module)
    ../../modules/nebula-node.nix

    # Restic backups to Backblaze B2
    ../../modules/restic-backup.nix
  ];

  # Enable restic backups
  kimb.restic.enable = true;
  kimb.restic.extraExclude = [
    "/home/kimb/.platformio" # ESP32 toolchains - reinstallable
    "/home/kimb/.android" # Android emulator images
    "/home/kimb/Android" # Android SDK
    "/home/kimb/.gradle" # Build cache
  ];

  # Nebula configuration
  kimb.nebula = {
    enable = true;
    openToPersonalDevices = true;
  };

  # Power management - use schedutil instead of auto-cpufreq
  services.auto-cpufreq.enable = lib.mkForce false;
  powerManagement.cpuFreqGovernor = "schedutil";

  # Boot configuration
  boot = {
    kernelModules = ["i915"];

    kernelPackages = pkgs.linuxKernel.packages.linux_6_18;

    # Disable Intel Panel Self Refresh - fixes Wayland freezes on KWin
    # See: https://wiki.archlinux.org/title/Intel_graphics
    kernelParams = ["i915.enable_psr=0"];

    kernelPatches = [
      {
        name = "elecom-huge-plus-patch";
        patch = pkgs.fetchpatch {
          url = "https://github.com/torvalds/linux/commit/b8e5fdf0bd022cd5493a5987ef66f5a24f8352d8.patch";
          sha256 = "sha256-TrnyN0B+IEnCk34Y24gD12EatWOvacFm3g67tI8e8Yk=";
        };
      }
    ];

    # systemd initrd
    initrd.systemd.enable = true;

    # Boot loader customizations
    loader.systemd-boot = {
      netbootxyz.enable = true;
      memtest86.enable = true;
    };

    plymouth = {
      enable = true;
      themePackages = [
        pkgs.adi1090x-plymouth-themes
      ];
      theme = "dna";
    };
  };

  # Network configuration
  networking = {
    # Host identification
    hostName = "marshmallow";

    # Wi-Fi backend
    networkmanager.wifi.backend = "iwd";

    # Use maitred router for DNS
    nameservers = let
      registry = import ../nebula-registry.nix;
    in [
      registry.nodes.maitred.ip # maitred router via Nebula
      "1.1.1.1" # Fallback
    ];

    # Firewall configuration
    firewall = {
      allowedTCPPorts = [9001];
      allowedUDPPorts = [65535];
    };
  };

  # Services configuration
  services = {
    # Thermal management - bypass DYTC platform check
    thermald.ignoreCpuidCheck = true;

    # Thunderbolt dock support
    hardware.bolt.enable = true;

    # Touchpad configuration
    libinput.mouse.naturalScrolling = true;

    # Wayland support for SDDM
    displayManager.sddm.wayland.enable = true;
    illum.enable = false;

    # Marshmallow-specific services
    yggdrasil = {
      enable = false;
      persistentKeys = true;
      openMulticastPort = true;
      group = "wheel";
      settings = {
        Peers = [
          "tcp://longseason.1200bps.xyz:13121"
          "tls://longseason.1200bps.xyz:13122"
          "quic://198.23.229.154:9003"
        ];
        LinkLocalTCPPort = 65535;
      };
    };

    keybase.enable = true;
    kbfs.enable = true;
    input-remapper.enable = true;

    syncthing = {
      enable = true;
      openDefaultPorts = true;
      user = "kimb";
      dataDir = "/home/kimb";
    };
  };

  # Programs configuration
  programs = {
    sway.enable = false;

    # Additional programs
    nix-ld.enable = true;
    mosh.enable = true;

    # Fish shell vendor configuration
    fish.vendor = {
      config.enable = true;
      functions.enable = true;
      completions.enable = true;
    };
  };

  # Intel graphics hardware configuration
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # For Broadwell+ iGPUs
    intel-gmmlib # Intel Graphics Memory Management Library
    intel-vaapi-driver # VAAPI driver for Intel graphics
    libva-vdpau-driver
    libvdpau-va-gl
    intel-compute-runtime # OpenCL support
  ];

  services.printing.drivers = [
    pkgs.brlaser
    pkgs.brgenml1lpr
    pkgs.brgenml1cupswrapper
  ];

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

  # Hardware acceleration for media
  environment = {
    sessionVariables = {
      VDPAU_DRIVER = "va_gl";
      LIBVA_DRIVER_NAME = "iHD"; # For newer Intel graphics
    };

    # Additional packages specific to marshmallow
    systemPackages = with pkgs; [
      keybase-gui
      kbfs
      gparted
      niri
      nh
    ];
  };

  # Swap configuration
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024; # 16GB
    }
  ];

  # zram compressed swap - used before file swap (priority 5 vs -2)
  zramSwap.enable = true;

  # User configuration
  users = {
    users.kimb = {
      extraGroups = ["docker" "dialout"];
      initialPassword = "recovery";
    };
    groups.dialout.members = ["kimb"];
  };

  # Trusted users for nix
  nix.settings.trusted-users = ["root" "kimb"];

  system.stateVersion = "24.11";
}
