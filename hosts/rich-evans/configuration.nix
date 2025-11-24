# Rich Evans - HP Mini PC home server
{
  config,
  lib,
  copyparty,
  pkgs,
  ...
}: let
  sshKeys = import ../ssh-keys.nix;
in {
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Role-based profiles
    ../profiles/base.nix
    ../profiles/server.nix

    # Services configuration
    ./services.nix

    # Server-specific modules
    ./guacamole.nix

    # Nebula mesh network with agenix
    ./nebula.nix

    # DNS server - DISABLED: moved to maitred router
    # ./dns.nix

    # Static networking
    ./networking.nix
  ];

  # Host identification
  networking.hostName = "rich-evans";

  # Boot configuration
  boot.loader.systemd-boot = {
    enable = true;
    edk2-uefi-shell.enable = true;
    netbootxyz.enable = true;
  };

  # Mount external storage
  fileSystems."/mnt/seagate" = {
    device = "/dev/disk/by-uuid/980870c5-7397-45dd-9f01-972f9b51d0f6";
    fsType = "ext4";
    options = ["defaults" "nofail"];
  };

  nixpkgs.overlays = [copyparty.overlays.default];

  # Server-specific services
  services = {
    miniflux = {
      enable = false;
      adminCredentialsFile = "/etc/miniflux-credentials";
      config = {
        LISTEN_ADDR = "0.0.0.0:8080";
      };
    };

    syncthing = {
      enable = true;
      openDefaultPorts = true;
      user = "kimb";
      dataDir = "/home/kimb";
      guiAddress = "0.0.0.0:8384";
    };

    # Tailscale with server routing
    tailscale.useRoutingFeatures = "server";

    # Mesh networking
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

    # Print server configuration
    printing = {
      browsing = true;
      drivers = [pkgs.brgenml1cupswrapper];
      openFirewall = true;
      listenAddresses = ["0.0.0.0:631"];
    };

    ipp-usb.enable = true;

    # Audio for server (legacy PulseAudio)
    pipewire.enable = false;
    pulseaudio.enable = true;
  };

  # User configuration with SSH keys
  users.users.kimb = {
    openssh.authorizedKeys.keys = sshKeys.authorizedKeys;
    initialPassword = "changeme";
  };

  # Programs configuration
  programs = {
    mosh.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
  };

  # Server-specific packages and environment
  environment = {
    systemPackages = with pkgs; [
      linux-firmware
      rclone
      nh
      zoxide
    ];

    # Override default shell setup for server
    shells = [pkgs.fish];
    variables.EDITOR = "nvim";
    sessionVariables.FLAKE = "/home/kimb/systems-flake";
  };

  users.defaultUserShell = pkgs.fish;

  # Trusted users for nix operations
  nix.settings.trusted-users = ["kimb" "root"];

  # Firewall configuration
  #
  networking.nameservers = let
    registry = import ../nebula-registry.nix;
  in [
    registry.nodes.maitred.ip # maitred router via Nebula
    "1.1.1.1" # Fallback
  ];

  networking.firewall = {
    allowedTCPPorts = [
      9001 # Existing service
      3923 # Copyparty HTTP
      3921 # Copyparty FTP
      3945 # Copyparty SMB
      3990 # Copyparty additional
      4822 # Guacamole daemon
      8080 # Guacamole web interface
    ];
    allowedTCPPortRanges = [
      {
        from = 12000;
        to = 12099;
      } # Copyparty dynamic ports
    ];
    allowedUDPPorts = [
      65535 # Existing
      69 # TFTP
      1900 # UPnP
      3969 # Copyparty TFTP
      5353 # mDNS/Bonjour
      20
    ];
  };
  networking.firewall.trustedInterfaces = ["nebula1" "lo"];

  system.stateVersion = "23.11";
}
