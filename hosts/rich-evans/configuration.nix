# Rich Evans - HP Mini PC home server
{
  config,
  lib,
  copyparty,
  pkgs,
  ...
}: {
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Role-based profiles
    ../profiles/base.nix
    ../profiles/server.nix

    # Server-specific modules
    ./nixarr.nix
    ./smarthome.nix
    # ./containers.nix
    
    # Nebula mesh network with agenix
    ./nebula.nix
  ];

  # Host identification
  networking.hostName = "rich-evans";

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.edk2-uefi-shell.enable = true;
  boot.loader.systemd-boot.netbootxyz.enable = true;


  # Server-specific services
  services.homepage-dashboard = {
    enable = true;
    openFirewall = true;
  };
  nixpkgs.overlays = [ copyparty.overlays.default ];
  services.copyparty.enable = true;

  services.miniflux = {
    enable = false;
    adminCredentialsFile = "/etc/miniflux-credentials";
    config = {
      LISTEN_ADDR = "0.0.0.0:8080";
    };
  };

  # Tailscale with server routing
  services.tailscale.useRoutingFeatures = "server";

  # Mesh networking
  services.yggdrasil = {
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
  services.printing = {
    browsing = true;
    drivers = [pkgs.brgenml1cupswrapper];
    openFirewall = true;
    listenAddresses = ["0.0.0.0:631"];
  };

  services.ipp-usb.enable = true;

  # Audio for server (legacy PulseAudio)
  services.pipewire.enable = false;
  services.pulseaudio.enable = true;

  # User configuration with SSH keys
  users.users.kimb = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZ+5yePKB5vKsm5MJg6SOZSwO0GCV9UBw5cmGx7NmEg mccartykim@zoho.com"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN2bgYbsq7Hp5RoM1Dlt59CdGEjvV6CoCi75pR4JiG5e mccartykim@zoho.com" # current historian ssh key
    ];
    initialPassword = "changeme";
  };

  # Additional programs
  programs.mosh.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Server-specific packages
  environment.systemPackages = with pkgs; [
    linux-firmware
    rclone
    nh
    zoxide
  ];

  # Override default shell setup for server
  users.defaultUserShell = pkgs.fish;
  environment.shells = [pkgs.fish];
  environment.variables.EDITOR = "nvim";
  environment.sessionVariables.FLAKE = "/home/kimb/systems-flake";

  # Trusted users for nix operations
  nix.settings.trusted-users = ["kimb" "root"];

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [9001];
    allowedUDPPorts = [65535];
  };

  system.stateVersion = "23.11";
}
