# Maitred - Datto 1000 router/firewall
{ config, lib, pkgs, inputs, ... }:

{
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
  ];

  # Host identification
  networking.hostName = "maitred";
  
  # Boot loader (adjust based on UEFI/BIOS during install)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable IP forwarding for routing
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Network configuration using systemd-networkd
  networking = {
    useDHCP = false;  # Managed by systemd-networkd
    useNetworkd = true;
    nftables.enable = lib.mkForce false;  # Override base profile - use iptables for router
    
    # Use rich-evans for DNS (via Nebula once configured)
    nameservers = [ 
      "192.168.68.200"  # Rich-evans on LAN
      "1.1.1.1"         # Cloudflare fallback
    ];
  };

  # Enable systemd-networkd
  systemd.network.enable = true;
  
  # WAN interface - DHCP from ISP
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "enp3s0";
    networkConfig = {
      DHCP = "yes";
      DNSOverTLS = false;
      DNSSEC = false;
      IPv6PrivacyExtensions = false;
    };
    dhcpV4Config = {
      RouteMetric = 512;
      UseDNS = false;  # Don't use ISP DNS
    };
    linkConfig.RequiredForOnline = "routable";
  };

  # LAN interface - Static IP
  systemd.network.networks."20-lan" = {
    matchConfig.Name = "enp2s0";
    address = [
      "192.168.68.1/24"
    ];
    networkConfig = {
      DHCPServer = true;
      IPv6SendRA = false;  # Disable IPv6 RA for now
    };
    dhcpServerConfig = {
      PoolOffset = 100;
      PoolSize = 100;  # .100 to .199
      EmitDNS = true;
      DNS = [ "192.168.68.1" ];  # Point clients to router DNS
      EmitRouter = true;
    };
  };

  # Firewall and NAT
  networking.nat = {
    enable = true;
    externalInterface = "enp3s0";  # WAN
    internalInterfaces = [ "enp2s0" ];  # LAN
  };

  networking.firewall = {
    enable = true;
    
    # Allow essential services
    allowedTCPPorts = [ 
      22    # SSH (consider restricting to LAN only)
      80    # HTTP (forwarded to blog container)
      443   # HTTPS (forwarded to blog container)
    ];
    
    allowedUDPPorts = [ 
      4242  # Nebula
    ];
    
    # Trust LAN interface
    trustedInterfaces = [ "enp2s0" ];
    
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
    '';
  };

  # Essential services
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    # Listen on all interfaces for now (restrict when router mode active)
    # listenAddresses = [
    #   { addr = "192.168.68.1"; port = 22; }  # TODO: When router mode enabled
    # ];
  };

  # Tailscale for backup access
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";  # Can route LAN traffic if needed
  };

  # Disable systemd-resolved to avoid port 53 conflict
  services.resolved.enable = false;

  # DNS Server with Nebula name resolution  
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [
          "0.0.0.0"       # Listen on all interfaces for now
          "127.0.0.1"     # localhost
        ];
        access-control = [
          "192.168.68.0/24 allow"
          "127.0.0.0/8 allow"
        ];
        # Auto-generate Nebula host entries from registry
        local-data = 
          let
            registry = import ../nebula-registry.nix;
          in
            builtins.map (name: "\"${name}.nebula. A ${registry.nodes.${name}.ip}\"") 
              (builtins.attrNames registry.nodes);
      };
    };
  };

  # Basic monitoring
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";  # Listen on all interfaces for now
    port = 9100;
  };

  # Network monitoring
  services.vnstat.enable = true;

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
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZ+5yePKB5vKsm5MJg6SOZSwO0GCV9UBw5cmGx7NmEg mccartykim@zoho.com"
    ];
    initialPassword = "changeme";  # Change after first login
  };

  # Sudo configured in base profile

  # Allow trusted users for remote deployment
  nix.settings.trusted-users = [ "kimb" "root" ];

  # Minimal installation
  documentation.enable = false;
  documentation.nixos.enable = false;
  
  system.stateVersion = "24.11";
}