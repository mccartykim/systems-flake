# Marshmallow - ThinkPad T490 (Intel graphics, gaming laptop)
{
  config,
  pkgs,
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

  # Host identification
  networking.hostName = "marshmallow";

  # Intel graphics hardware configuration
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # For Broadwell+ iGPUs
    intel-gmmlib # Intel Graphics Memory Management Library
    vaapiIntel # VAAPI driver for Intel graphics
    vaapiVdpau
    libvdpau-va-gl
    intel-compute-runtime # OpenCL support
  ];

  # Intel-specific optimizations
  boot.kernelModules = ["i915"];
  boot.kernelParams = [
    "i915.enable_fbc=1"
    "i915.enable_psr=2"
  ];

  # Hardware acceleration for media
  environment.sessionVariables = {
    VDPAU_DRIVER = "va_gl";
    LIBVA_DRIVER_NAME = "iHD"; # For newer Intel graphics
  };

  # Boot loader customizations
  boot.loader.systemd-boot.netbootxyz.enable = true;
  boot.loader.systemd-boot.memtest86.enable = true;

  # systemd initrd
  boot.initrd.systemd.enable = true;

  # Swap configuration
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024; # 16GB
    }
  ];

  # Wi-Fi backend
  networking.networkmanager.wifi.backend = "iwd";

  # Touchpad configuration
  services.libinput.mouse.naturalScrolling = true;

  # Wayland support for SDDM
  services.displayManager.sddm.wayland.enable = true;
  programs.sway.enable = false;
  services.illum.enable = false;

  # Additional user groups
  users.users.kimb.extraGroups = ["docker" "dialout"];
  users.users.kimb.initialPassword = "recovery";
  users.groups.dialout.members = ["kimb"];

  # Marshmallow-specific services
  services.yggdrasil = {
    enable = true;
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

  services.keybase.enable = true;
  services.kbfs.enable = true;

  # Additional packages specific to marshmallow
  environment.systemPackages = with pkgs; [
    keybase-gui
    kbfs
    gparted
    niri
    nh
  ];

  # Additional programs
  programs.nix-ld.enable = true;
  programs.mosh.enable = true;

  # Fish shell vendor configuration
  programs.fish.vendor = {
    config.enable = true;
    functions.enable = true;
    completions.enable = true;
  };

  # Trusted users for nix
  nix.settings.trusted-users = ["root" "kimb"];

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [9001];
    allowedUDPPorts = [65535];
  };

  system.stateVersion = "23.05";
}
