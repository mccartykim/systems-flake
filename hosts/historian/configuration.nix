# Historian - Desktop (AMD graphics, gaming, AI/ML workloads)
{
  config,
  pkgs,
  ...
}:
{
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Role-based profiles
    ../profiles/base.nix
    ../profiles/desktop.nix
    ../profiles/gaming.nix
  ];
  virtualisation.containers.enable = true;
  virtualisation = {
    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  programs.nix-ld.enable = true;

  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.virtualbox.host.enable = true;
  virtualisation.virtualbox.host.enableKvm = true;
  virtualisation.virtualbox.host.enableExtensionPack = true;
  virtualisation.virtualbox.host.addNetworkInterface = false;

  # Host identification
  networking.hostName = "historian";

  # AMD graphics hardware configuration
  services.xserver.videoDrivers = [ "amdgpu" ];

  # AMD GPU hardware acceleration
  hardware.graphics.extraPackages = with pkgs; [
    amdvlk
    rocmPackages.clr.icd
  ];

  # ROCm support for compute workloads
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  # AMD-specific kernel modules
  boot.kernelModules = [ "amdgpu" ];
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_6_15;

  # Environment variables for AMD
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "radeonsi";
    VDPAU_DRIVER = "radeonsi";
  };

  # Boot loader customizations
  boot.loader.systemd-boot.netbootxyz.enable = true;
  boot.loader.systemd-boot.memtest86.enable = true;

  # Memory management - use zram instead of file swap
  zramSwap.enable = true;

  # Wi-Fi backend
  networking.networkmanager.wifi.backend = "iwd";

  # AMD-specific configuration
  hardware.amdgpu.opencl.enable = true;
  nixpkgs.config.rocmSupport = true;

  # AI/ML services with ROCm acceleration
  services.ollama = {
    enable = true;
    acceleration = "rocm";
    rocmOverrideGfx = "11.5.0";
  };

  # Enable Sunshine for game streaming
  services.sunshine.enable = true;

  # Additional services
  services.xrdp = {
    enable = true;
    openFirewall = true;
  };

  # Additional user groups
  users.users.kimb = {
    description = "Kimberly";
    extraGroups = [
      "docker"
      "dialout"
      "input"
    ];
  };

  # Additional programs
  programs.appimage.enable = true;

  # Additional packages specific to historian
  environment.systemPackages = with pkgs; [
    # ROCm packages for compute
    rocmPackages.rocm-smi
    radeontop
    # Historian specific packages
    legendary-gl
    sunshine
    toolbox
    cachix
    lmstudio
    tealdeer
    rebar3
    erlang
    gleam
  ];

  # Avahi for service discovery
  services.avahi.publish = {
    enable = true;
    userServices = true;
  };

  # Network interface configuration
  networking.interfaces.eno2.wakeOnLan = {
    enable = true;
    policy = [ "unicast" ];
  };

  # Extended firewall configuration for streaming
  networking.firewall = {
    allowedTCPPorts = [
      47984
      47989
      47990
      48000
      48010
    ];
    allowedUDPPortRanges = [
      {
        from = 47998;
        to = 48020;
      }
      {
        from = 8000;
        to = 8010;
      }
    ];
  };

  system.stateVersion = "23.11";
}
