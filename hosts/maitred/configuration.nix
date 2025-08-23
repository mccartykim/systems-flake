# Maitred - Datto 1000 router/firewall
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Hardware configuration will be generated during install
    ./hardware-configuration.nix

    # Base profile for all hosts
    ../profiles/base.nix

    # Nebula mesh network with agenix
    ./nebula.nix

    # Reverse proxy container
    ./reverse-proxy.nix

    # Blog service container
    ./blog-service.nix

    # Dynamic DNS
    ./dns-update.nix

    # Monitoring (Prometheus & Grafana)
    ./monitoring.nix

    # Homepage dashboard
    ./homepage.nix

    # Authelia authentication
    ./authelia.nix
  ];

  # Boot configuration
  boot = {
    # Boot loader (adjust based on UEFI/BIOS during install)
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Enable IP forwarding for routing
    kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      # Enable hairpin NAT for all interfaces
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
    };
  };

  # Network configuration using systemd-networkd
  networking = {
    # Host identification
    hostName = "maitred";

    useDHCP = false; # Managed by systemd-networkd
    useNetworkd = true;
    nftables.enable = lib.mkForce false; # Override base profile - use iptables for router

    # Override base profile - maitred uses its own unbound DNS server only
    nameservers = ["127.0.0.1"];

    # Firewall and NAT
    nat = {
      enable = true;
      externalInterface = "enp3s0"; # WAN
      internalInterfaces = ["enp2s0"]; # LAN
    };

    firewall = {
      enable = true;

      # Allow essential services (SSH removed from public access)
      allowedTCPPorts = [
        80 # HTTP (forwarded to blog container)
        443 # HTTPS (forwarded to blog container)
      ];

      allowedUDPPorts = [
        4242 # Nebula
      ];

      # Trust LAN interface
      trustedInterfaces = ["enp2s0"];

      # Log dropped packets (for debugging)
      logRefusedConnections = false;

      # Additional rules
      extraCommands = ''
        # Drop all forwarding by default
        iptables -P FORWARD DROP

        # Allow established connections
        iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

        # Allow LAN to WAN
        iptables -A FORWARD -i enp2s0 -o enp3s0 -j ACCEPT

        # Block WAN to LAN (except established)
        iptables -A FORWARD -i enp3s0 -o enp2s0 -m conntrack --ctstate NEW -j DROP

        # Removed hairpin NAT - using split-brain DNS instead
      '';
    };
  };

  # System daemon configuration
  systemd.network = {
    enable = true;

    # WAN interface - DHCP from ISP
    networks."10-wan" = {
      matchConfig.Name = "enp3s0";
      networkConfig = {
        DHCP = "yes";
        DNSOverTLS = false;
        DNSSEC = false;
        IPv6PrivacyExtensions = false;
      };
      dhcpV4Config = {
        RouteMetric = 512;
        UseDNS = false; # Don't use ISP DNS
        # Fix FiOS DHCP lease renewal issues
        ClientIdentifier = "mac";
        RequestBroadcast = true;
        # Use defaults for other options - NixOS systemd-networkd module is restrictive
      };
      linkConfig.RequiredForOnline = "routable";
    };

    # LAN interface - Static IP
    networks."20-lan" = {
      matchConfig.Name = "enp2s0";
      address = [
        "192.168.69.1/24"
      ];
      networkConfig = {
        DHCPServer = true;
        IPv6SendRA = false; # Disable IPv6 RA for now
      };
      dhcpServerConfig = {
        PoolOffset = 100;
        PoolSize = 100; # .100 to .199
        EmitDNS = true;
        DNS = ["192.168.69.1"]; # Point clients to router DNS
        EmitRouter = true;
      };
    };
  };

  # Systemd services
  systemd.services.copyparty-proxy = {
    description = "Copyparty proxy to rich-evans";
    after = ["network.target" "nebula@mesh.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:3923,fork,reuseaddr TCP4:10.100.0.40:3923";
      Restart = "always";
      RestartSec = "5";
      User = "nobody";
      Group = "nogroup";
    };
  };

  # Guacamole proxy service - DISABLED 
  # TODO: Re-enable when Guacamole is working properly
  # systemd.services.guacamole-proxy = {
  #   description = "Guacamole proxy to rich-evans";
  #   after = ["network.target" "nebula@mesh.service"];
  #   wantedBy = ["multi-user.target"];
  #   serviceConfig = {
  #     ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:8080,fork,reuseaddr TCP4:10.100.0.40:8080";
  #     Restart = "always";
  #     RestartSec = "5";
  #     User = "nobody";
  #     Group = "nogroup";
  #   };
  # };

  # System services
  services = {
    # Essential services
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
      # Restrict SSH to LAN and Nebula VPN only - NO public access
      listenAddresses = [
        {
          addr = "192.168.69.1";
          port = 22;
        } # LAN access
        {
          addr = "10.100.0.50";
          port = 22;
        } # Nebula VPN access
      ];
    };

    # Tailscale for backup access
    tailscale = {
      enable = true;
      useRoutingFeatures = "server"; # Can route LAN traffic if needed
    };

    # Disable systemd-resolved to avoid port 53 conflict
    resolved.enable = false;

    # DNS Server with Nebula name resolution
    unbound = {
      enable = true;
      settings = {
        server = {
          interface = [
            "0.0.0.0" # Listen on all interfaces for now
            "127.0.0.1" # localhost
          ];
          access-control = [
            "192.168.69.0/24 allow"
            "192.168.100.0/24 allow" # Container network
            "127.0.0.0/8 allow"
          ];
          # Local DNS entries for Nebula hosts and local domains
          local-data = let
            registry = import ../nebula-registry.nix;
            nebula-hosts =
              builtins.map (name: "\"${name}.nebula. A ${registry.nodes.${name}.ip}\"")
              (builtins.attrNames registry.nodes);
            local-domains = [
              # Split-brain DNS: LAN clients get container IP for kimb.dev domains
              "\"kimb.dev. A 192.168.100.2\""
              "\"auth.kimb.dev. A 192.168.100.2\""
              "\"blog.kimb.dev. A 192.168.100.2\""
              "\"home.kimb.dev. A 192.168.100.2\""
              "\"grafana.kimb.dev. A 192.168.100.2\""
              "\"prometheus.kimb.dev. A 192.168.100.2\""
              "\"copyparty.kimb.dev. A 192.168.100.2\""
              # "\"remote.kimb.dev. A 192.168.100.2\""  # DISABLED - Guacamole not ready
            ];
          in
            nebula-hosts ++ local-domains;
        };
      };
    };

    # Basic monitoring (restricted to LAN)
    prometheus.exporters.node = {
      enable = true;
      listenAddress = "192.168.69.1"; # LAN only - no public access
      port = 9100;
    };

    # Network monitoring
    vnstat.enable = true;
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    iftop
    tcpdump
    dig
    traceroute
    nmap
    ethtool
    conntrack-tools
  ];

  # User configuration
  users.users.kimb = {
    isNormalUser = true;
    description = "Kimberly";
    extraGroups = ["wheel" "networkmanager"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZ+5yePKB5vKsm5MJg6SOZSwO0GCV9UBw5cmGx7NmEg mccartykim@zoho.com"
    ];
    initialPassword = "changeme"; # CRITICAL: Change this password immediately after deployment!
  };

  # Allow trusted users for remote deployment
  nix.settings.trusted-users = ["kimb" "root"];

  # Minimal installation
  documentation.enable = false;
  documentation.nixos.enable = false;

  system.stateVersion = "24.11";
}
