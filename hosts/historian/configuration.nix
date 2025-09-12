# Historian - Desktop (AMD graphics, gaming, AI/ML workloads)
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
  # Virtualization configuration
  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };

    libvirtd.enable = true;
    virtualbox.host = {
      enable = true;
      enableKvm = true;
      enableExtensionPack = true;
      addNetworkInterface = false;
    };
  };

  # Host identification and networking configuration
  networking = {
    hostName = "historian";

    # Wi-Fi backend
    networkmanager.wifi.backend = "iwd";

    # Network interface configuration
    interfaces.eno2.wakeOnLan = {
      enable = true;
      policy = ["unicast"];
    };

    # Use maitred router for DNS
    nameservers = let
      registry = import ../nebula-registry.nix;
    in [
      registry.nodes.maitred.ip # maitred router via Nebula
      "1.1.1.1" # Fallback
    ];

    # Extended firewall configuration for streaming
    firewall = {
      allowedTCPPorts = [
        47984
        47989
        47990
        48000
        48010
        22000
      ];
      allowedUDPPorts = [4242 22000]; # Nebula
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
      trustedInterfaces = [
        "virbr0"
        "nebula1"
      ];
    };
  };

  # AMD graphics hardware configuration
  services.xserver.videoDrivers = ["amdgpu"];

  # AMD GPU hardware acceleration
  hardware.graphics.extraPackages = with pkgs; [
    amdvlk
    rocmPackages.clr.icd
  ];

  # AMD-specific configuration
  hardware.amdgpu.opencl.enable = true;

  # ROCm support for compute workloads
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  # Boot configuration
  boot = {
    # AMD-specific kernel modules
    kernelModules = ["amdgpu" "kvm-amd"];
    kernelPackages = pkgs.linuxPackages_latest;

    # Boot loader customizations
    loader.systemd-boot = {
      netbootxyz.enable = true;
      memtest86.enable = true;
    };
  };

  # Environment configuration
  environment = {
    # Environment variables for AMD
    sessionVariables = {
      LIBVA_DRIVER_NAME = "radeonsi";
      VDPAU_DRIVER = "radeonsi";
    };

    # Additional packages specific to historian
    systemPackages = with pkgs; [
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
  };

  # Memory management - use zram instead of file swap
  zramSwap.enable = true;

  # AMD-specific configuration
  nixpkgs.config.rocmSupport = true;

  # Services configuration
  services = {
    # AI/ML services with ROCm acceleration
    ollama = {
      enable = true;
      acceleration = "rocm";
      rocmOverrideGfx = "11.5.0";
    };

    syncthing = {
      enable = true;
      openDefaultPorts = true;
      user = "kimb";
      dataDir = "/home/kimb";
    };

    # Enable Sunshine for game streaming
    sunshine.enable = true;

    # Additional services
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
    extraGroups = [
      "docker"
      "dialout"
      "input"
      "libvirtd"
    ];
  };

  # Programs configuration
  programs = {
    nix-ld.enable = true;
    virt-manager.enable = true;
    appimage.enable = true;
  };

  system.stateVersion = "23.11";
}
