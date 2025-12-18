# Maitred - Datto 1000 router/firewall
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  sshKeys = import ../ssh-keys.nix;
in {
  imports = [
    # Hardware configuration will be generated during install
    ./hardware-configuration.nix

    # Base profile for all hosts
    ../profiles/base.nix

    # Nebula mesh network (consolidated module)
    ../../modules/nebula-node.nix

    # Ephemeral nebula networks (buildnet + containernet)
    ./ephemeral-networks.nix

    # Reverse proxy container
    ./reverse-proxy.nix

    # Blog service container
    ./blog-service.nix

    # Dynamic DNS (includes cloudflare secret)
    ./dns-update.nix

    # Monitoring (Prometheus & Grafana)
    ./monitoring.nix

    # Homepage dashboard
    ./homepage.nix

    # Authelia authentication
    ./authelia.nix

    # Printer configuration
    ./printer.nix
  ];

  # Nebula configuration (router + SMB printer sharing)
  kimb.nebula = {
    enable = true;
    openToPersonalDevices = true;
    extraInboundRules = [
      # SMB for printing group only
      { port = 139; proto = "tcp"; groups = ["printing"]; }
      { port = 445; proto = "tcp"; groups = ["printing"]; }
      { port = 137; proto = "udp"; groups = ["printing"]; }
      { port = 138; proto = "udp"; groups = ["printing"]; }
    ];
  };

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

  services.printing = {
    enable = true;
    defaultShared = true;
    listenAddresses = ["*:631"];
    allowFrom = ["all"];
    browsing = true;
    drivers = [
      pkgs.brlaser
      pkgs.brgenml1lpr
      pkgs.brgenml1cupswrapper
    ];
  };
  services.ipp-usb.enable = true;

  services.samba = {
    enable = true;
    package = pkgs.samba.override {
      enablePrinting = true;
      cups = pkgs.cups;
    };
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "Maitred Print Server";
        "netbios name" = "maitred";
        "security" = "user";
        "hosts allow" = "192.168.69. 10.100. 127."; # LAN + Nebula, not WAN
        "guest account" = "nobody";
        "map to guest" = "bad user";
        "load printers" = "yes";
        "printing" = "cups";
        "printcap name" = "cups";
      };
      printers = {
        "comment" = "All Printers";
        "path" = "/var/spool/samba";
        "public" = "yes";
        "browseable" = "yes";
        "guest ok" = "yes";
        "writable" = "no";
        "printable" = "yes";
        "create mode" = 0700;
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  systemd.tmpfiles.rules = [
    "d /var/spool/samba 1777 root root -"
  ];

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
      internalInterfaces = ["enp2s0" "ve-+"]; # LAN + containers
    };

    firewall = {
      enable = true;

      # Allow essential services (SSH removed from public access)
      allowedTCPPorts = [
        53 # DNS for containers (TCP fallback)
        80 # HTTP (forwarded to blog container)
        443 # HTTPS (forwarded to blog container)
        631 # CUPS/IPP printer sharing
      ];

      allowedUDPPorts = [
        53 # DNS for containers
        4242 # Nebula
      ];

      # Trust LAN and container interfaces
      trustedInterfaces = ["enp2s0" "ve-+"];

      # Log dropped packets (for debugging)
      logRefusedConnections = false;

      # Additional rules
      extraCommands = let
        proxyIP = config.kimb.services.reverse-proxy.containerIP;
      in ''
        # LAN to container port forwarding (split-brain DNS support)
        iptables -t nat -A PREROUTING -i enp2s0 -d 192.168.69.1 -p tcp --dport 80 -j DNAT --to-destination ${proxyIP}:80
        iptables -t nat -A PREROUTING -i enp2s0 -d 192.168.69.1 -p tcp --dport 443 -j DNAT --to-destination ${proxyIP}:443

        # Drop all forwarding by default
        iptables -P FORWARD DROP

        # Allow established connections
        iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

        # Allow container-to-container traffic
        iptables -A FORWARD -i ve-+ -o ve-+ -j ACCEPT

        # Allow containers to WAN
        iptables -A FORWARD -i ve-+ -o enp3s0 -j ACCEPT

        # Allow reverse-proxy container to access vacuum only (by source IP)
        iptables -A FORWARD -s ${proxyIP} -o enp2s0 -d 192.168.69.177 -j ACCEPT

        # Allow LAN to WAN
        iptables -A FORWARD -i enp2s0 -o enp3s0 -j ACCEPT

        # Allow LAN to containers
        iptables -A FORWARD -i enp2s0 -o ve-+ -j ACCEPT

        # Block WAN to LAN (except established)
        iptables -A FORWARD -i enp3s0 -o enp2s0 -m conntrack --ctstate NEW -j DROP

        # Removed hairpin NAT - using split-brain DNS instead
      '';
    };
  };

  # System daemon configuration
  systemd.network = {
    enable = true;

    # Container networking - point-to-point for each container
    networks."40-container-ve" = {
      matchConfig.Name = "ve-*";
      networkConfig = {
        IPv4Forwarding = true;
        IPv6Forwarding = true;
      };
    };

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
      dhcpServerStaticLeases = [
        {
          # Robot vacuum running Valetudo
          MACAddress = "70:c9:32:1f:ba:d0";
          Address = "192.168.69.177";
        }
      ];
    };
  };

  # Dynamic service proxies for enabled services on remote hosts
  systemd.services = let
    cfg = config.kimb;
    registry = import ../nebula-registry.nix;

    # Create proxy services for enabled remote services
    mkProxyService = serviceName: service: let
      hostIP = registry.nodes.${service.host}.ip or "127.0.0.1";
    in
      lib.nameValuePair "${serviceName}-proxy" {
        description = "${serviceName} proxy to ${service.host}";
        after = ["network.target" "nebula@mesh.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:${toString service.port},fork,reuseaddr TCP4:${hostIP}:${toString service.port}";
          Restart = "always";
          RestartSec = "5";
          User = "nobody";
          Group = "nogroup";
        };
      };

    # Generate proxy services for enabled remote services
    # Proxy ALL remote services regardless of container status
    remoteServices =
      lib.filterAttrs (
        name: service:
          service.enable && service.host != "maitred"
      )
      cfg.services;
  in
    lib.mapAttrs' mkProxyService remoteServices;

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
          # Local DNS entries for Nebula hosts and enabled services
          local-data = let
            registry = import ../nebula-registry.nix;
            cfg = config.kimb;

            # Nebula host entries
            nebula-hosts =
              builtins.map (name: "\"${name}.nebula. A ${registry.nodes.${name}.ip}\"")
              (builtins.attrNames registry.nodes);

            # Generate DNS entries for enabled public services
            # Use router's LAN IP for split-brain DNS (192.168.69.1)
            serviceDomains =
              lib.mapAttrsToList (
                name: service: "\"${service.subdomain}.${cfg.domain}. A 192.168.69.1\""
              ) (lib.filterAttrs (
                  name: service:
                    service.enable && service.publicAccess
                )
                cfg.services);

            # Root domain entry
            rootDomain = ["\"${cfg.domain}. A 192.168.69.1\""];

            # Vacuum entry - point to router for Caddy proxy
            vacuumEntry = ["\"vacuum.${cfg.domain}. A 192.168.69.1\""];
          in
            nebula-hosts ++ rootDomain ++ serviceDomains ++ vacuumEntry;
        };
      };
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
    openssh.authorizedKeys.keys = sshKeys.authorizedKeys;
    initialPassword = "changeme"; # CRITICAL: Change this password immediately after deployment!
  };

  # Allow trusted users for remote deployment
  nix.settings.trusted-users = ["kimb" "root"];

  # Minimal installation
  documentation.enable = false;
  documentation.nixos.enable = false;

  system.stateVersion = "24.11";
}
