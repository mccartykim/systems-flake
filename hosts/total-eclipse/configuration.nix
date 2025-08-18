# Total Eclipse - Gaming desktop (NVIDIA graphics, streaming)
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
    ../profiles/gaming.nix
    
    # Nebula mesh network with agenix
    ./nebula.nix
  ];

  # Host identification
  networking.hostName = "total-eclipse";

  # NVIDIA graphics hardware configuration
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = true; # Use open-source drivers
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # CUDA support
  nixpkgs.config.cudaSupport = true;

  # OpenGL and hardware acceleration
  hardware.graphics.extraPackages = with pkgs; [
    vaapiVdpau
    libvdpau-va-gl
  ];

  # Environment variables for NVIDIA
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    VDPAU_DRIVER = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  # Boot loader - GRUB for legacy system
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub = {
    enable = true;
    device = "/dev/nvme0n1";
  };

  # Swap configuration
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 32 * 1024; # 32GB
    }
  ];

  # Wi-Fi backend
  networking.networkmanager.wifi.backend = "iwd";

  # Enable Sunshine for game streaming
  services.sunshine.enable = true;

  # Additional services
  services.ollama.enable = true;
  services.xrdp = {
    enable = true;
    openFirewall = true;
  };

  # Additional user groups
  users.users.kimb = {
    description = "Kimberly";
    extraGroups = ["input"];
  };

  # Container support for NVIDIA
  hardware.nvidia-container-toolkit.enable = true;

  # Additional packages specific to total-eclipse
  environment.systemPackages = with pkgs; [
    # NVIDIA packages
    nvtopPackages.nvidia
    nvidia-container-toolkit
    # Total-eclipse specific packages
    legendary-gl
    sunshine
    toolbox
    tealdeer
  ];

  # Avahi for service discovery
  services.avahi.publish = {
    enable = true;
    userServices = true;
  };

  # Network interface configuration
  networking.interfaces.eno2.wakeOnLan = {
    enable = true;
    policy = ["unicast"];
  };

  # Use rich-evans for DNS
  networking.nameservers = [ 
    "10.100.0.40"  # Rich-evans via Nebula
    "1.1.1.1"      # Fallback
  ];

  # Extended firewall configuration for streaming
  networking.firewall = {
    allowedTCPPorts = [47984 47989 47990 48000 48010];
    allowedUDPPorts = [ 4242 ]; # Nebula
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
