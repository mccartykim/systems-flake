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

  # Nebula configuration (certs generated via `nix run .#generate-nebula-certs`)
  kimb.nebula = {
    enable = true;
    openToPersonalDevices = true;
    # Allow servers (like rich-evans) to access Ollama API
    extraInboundRules = [
      {
        port = 11434;
        proto = "tcp";
        group = "servers";
      }
    ];
  };

  # Distributed builds
  kimb.distributedBuilds = {
    # enable = true; # Already enabled via commonModules

    # Buildnet disabled - CA cert needs regeneration
    # buildnet.enable = true;

    # Claude Code SSH key - can only run nix-daemon, no shell access
    builderOnlyKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKcpY/DdbidptJJsrr3DgZyrwMYW79cpRwqwb5GbCGy7 claude"
    ];
  };
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
  };

  # Host identification and networking configuration
  networking = {
    hostName = "historian";

    # Wi-Fi backend
    networkmanager.wifi.backend = "iwd";

    # Network interface configuration
    interfaces.eno1.wakeOnLan = {
      enable = true;
      policy = ["magic" "unicast"];
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

    # Increase GTT for large model inference (4GB VRAM + 56GB GTT ≈ 60GB for ROCm)
    kernelParams = ["amdgpu.gttsize=57344"];

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
      # Media
      vlc
      # Email
      mu
      isync
    ];
  };

  # AMD-specific configuration
  nixpkgs.config.rocmSupport = true;

  # Wait for Thunderbolt dock before starting display manager
  # (CalDigit TS3 Plus needs time to establish DP tunnel over USB4)
  systemd.services.display-manager = {
    after = ["bolt.service"];
    wants = ["bolt.service"];
  };

  # Auto-login for TV use
  services.displayManager.autoLogin = {
    enable = true;
    user = "tv";
  };

  # Disable screen lock and blanking for TV
  services.xserver.displayManager.sessionCommands = ''
    ${pkgs.xset}/bin/xset s off
    ${pkgs.xset}/bin/xset dpms 0 0 0
  '';

  # TV user for living room - Steam Big Picture, Firefox, Flatpak
  users.users.tv = {
    isNormalUser = true;
    description = "Living Room TV";
    extraGroups = ["video" "audio" "input" "users"];
    # No password - auto-login only
    hashedPassword = "";
    shell = pkgs.bash;
  };

  # Firefox auto-launch for TV user
  systemd.user.services.firefox-tv = {
    description = "Firefox for TV";
    wantedBy = ["graphical-session.target"];
    after = ["graphical-session-started.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.firefox}/bin/firefox --new-window about:blank";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    environment = {
      DISPLAY = ":0";
    };
  };

  # Services configuration
  services = {
    # Smart card daemon for YubiKey support
    pcscd.enable = true;

    # Thunderbolt device authorization (for dock enrollment)
    hardware.bolt.enable = true;

    # AI/ML services with ROCm acceleration
    ollama = {
      enable = true;
      package = pkgs.ollama-rocm;
      rocmOverrideGfx = "11.5.0";
      openFirewall = true;
      host = "0.0.0.0";
      # Enable parallel inference for batch processing (6 concurrent requests)
      environmentVariables = {
        OLLAMA_NUM_PARALLEL = "6";
        OLLAMA_FLASH_ATTENTION = "1"; # Reduce VRAM usage
        OLLAMA_KV_CACHE_TYPE = "q8_0"; # Further VRAM reduction
      };
    };
    open-webui = {
      enable = false;
      host = "0.0.0.0";
      openFirewall = true;
      environment = {
        OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      };
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

  # Enable cross-compilation for ARM via QEMU emulation
  boot.binfmt.emulatedSystems = ["armv6l-linux" "aarch64-linux"];

  # Programs configuration
  programs = {
    nix-ld.enable = true;
    virt-manager.enable = true;
    appimage.enable = true;
  };

  system.stateVersion = "23.11";
}
