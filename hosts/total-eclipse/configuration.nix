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

  # Host identification and networking configuration
  networking = {
    hostName = "total-eclipse";
    # Wi-Fi backend
    networkmanager.wifi.backend = "iwd";

    # Network interface configuration
    interfaces.eno2.wakeOnLan = {
      enable = true;
      policy = ["unicast"];
    };

    # Use rich-evans for DNS
    nameservers = [
      "10.100.0.40" # Rich-evans via Nebula
      "1.1.1.1" # Fallback
    ];

    # Extended firewall configuration for streaming
    firewall = {
      allowedTCPPorts = [47984 47989 47990 48000 48010];
      allowedUDPPorts = [4242]; # Nebula
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
  };

  # NVIDIA graphics hardware configuration
  services.xserver.videoDrivers = ["nvidia"];

  # CUDA support
  nixpkgs.config.cudaSupport = true;

  # Hardware configuration
  hardware = {
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      open = true; # Use open-source drivers
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    # OpenGL and hardware acceleration
    graphics.extraPackages = with pkgs; [
      vaapiVdpau
      libvdpau-va-gl
    ];

    # Container support for NVIDIA
    nvidia-container-toolkit.enable = true;
  };

  # Environment configuration
  environment = {
    # Environment variables for NVIDIA
    sessionVariables = {
      LIBVA_DRIVER_NAME = "nvidia";
      VDPAU_DRIVER = "nvidia";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    };

    # Additional packages specific to total-eclipse
    systemPackages = with pkgs; [
      # NVIDIA packages
      nvtopPackages.nvidia
      nvidia-container-toolkit
      # Total-eclipse specific packages
      legendary-gl
      sunshine
      toolbox
      tealdeer
    ];
  };

  # Boot loader - GRUB for legacy system
  boot.loader = {
    systemd-boot.enable = false;
    grub = {
      enable = true;
      device = "/dev/nvme0n1";
    };
  };

  # Swap configuration
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 32 * 1024; # 32GB
    }
  ];

  # Services configuration
  services = {
    # Enable Sunshine for game streaming
    sunshine.enable = true;

    # Additional services
    ollama.enable = true;
    xrdp = {
      enable = true;
      openFirewall = true;
    };

    # Avahi for service discovery
    avahi.publish = {
      enable = true;
      userServices = true;
    };
  };

  # Additional user groups
  users.users.kimb = {
    description = "Kimberly";
    extraGroups = ["input"];
  };

  system.stateVersion = "23.11";
}
