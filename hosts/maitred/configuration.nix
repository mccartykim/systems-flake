# Maitred - Datto 1000 router/firewall
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    # Hardware configuration will be generated during install
    ./hardware-configuration.nix
    
    # TODO: Enable Nebula once we have SSH host key and certificates
    # ./nebula.nix
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
    useDHCP = true;  # Use DHCP for now - will get IP from existing router
    # useNetworkd = true;
    
    # Use rich-evans for DNS (via Nebula once configured)
    nameservers = [ 
      "192.168.68.200"  # Rich-evans on LAN
      "1.1.1.1"         # Cloudflare fallback
    ];
  };

  # TODO: Enable these when ready to take over router duties
  # # WAN interface - DHCP from ISP
  # systemd.network.networks."10-wan" = {
  #   matchConfig.Name = "enp3s0";
  #   networkConfig = {
  #     DHCP = "yes";
  #     DNSOverTLS = false;
  #     DNSSEC = false;
  #     IPv6PrivacyExtensions = false;
  #   };
  #   dhcpV4Config = {
  #     RouteMetric = 512;
  #     UseDNS = false;  # Don't use ISP DNS
  #   };
  #   linkConfig.RequiredForOnline = "routable";
  # };

  # # LAN interface - Static IP
  # systemd.network.networks."20-lan" = {
  #   matchConfig.Name = "enp2s0";
  #   address = [
  #     "192.168.68.1/24"
  #   ];
  #   networkConfig = {
  #     DHCPServer = true;
  #     IPv6SendRA = false;  # Disable IPv6 RA for now
  #   };
  #   dhcpServerConfig = {
  #     PoolOffset = 100;
  #     PoolSize = 100;  # .100 to .199
  #     EmitDNS = true;
  #     DNS = [ "192.168.68.200" ];  # Point clients to rich-evans
  #     EmitRouter = true;
  #   };
  # };

  # # Firewall and NAT
  # networking.nat = {
  #   enable = true;
  #   externalInterface = "enp3s0";  # WAN
  #   internalInterfaces = [ "enp2s0" ];  # LAN
  # };

  networking.firewall = {
    enable = true;
    
    # Allow essential services
    allowedTCPPorts = [ 
      22    # SSH (consider restricting to LAN only)
    ];
    
    allowedUDPPorts = [ 
      # 4242  # Nebula (when enabled)
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

  # Basic monitoring
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "192.168.68.1";
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

  # Enable sudo
  security.sudo.wheelNeedsPassword = true;

  # Minimal installation
  documentation.enable = false;
  documentation.nixos.enable = false;
  
  system.stateVersion = "24.11";
}