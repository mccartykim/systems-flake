# Marshmallow - ThinkPad T490 (Intel graphics, gaming laptop)
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
    ../profiles/desktop.nix
    ../profiles/laptop.nix
    ../profiles/gaming.nix

    # Nebula mesh network with agenix
    ./nebula.nix
  ];

  # Boot configuration
  boot = {
    # Intel-specific optimizations
    kernelModules = ["i915"];
    kernelParams = [
      "i915.enable_fbc=1"
      "i915.enable_psr=2"
    ];

    # systemd initrd
    initrd.systemd.enable = true;

    # Boot loader customizations
    loader.systemd-boot = {
      netbootxyz.enable = true;
      memtest86.enable = true;
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
    vaapiIntel # VAAPI driver for Intel graphics
    vaapiVdpau
    libvdpau-va-gl
    intel-compute-runtime # OpenCL support
  ];

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
