# DNS server configuration for rich-evans
{ config, lib, pkgs, ... }:

let
  # Define Nebula network hosts - single source of truth
  nebulaNodes = {
    lighthouse = "10.100.0.1";
    rich-evans = "10.100.0.40";  # Adjust based on actual config
    bartleby = "10.100.0.3";
    marshmallow = "10.100.0.4";
    historian = "10.100.0.10";  # This is historian's actual IP
    total-eclipse = "10.100.0.6";
  };
  
  # Define local network static IPs
  localNodes = {
    router = "192.168.68.1";  # Your router's static IP
    rich-evans = "192.168.68.200";  # Rich-evans on LAN (static, high range)
    historian = "192.168.68.105";  # Historian on LAN
    # Add other static LAN IPs here as needed
  };
  
  # Generate DNS A records from nodes
  generateARecords = domain: nodes:
    lib.mapAttrsToList (name: ip: 
      ''"${name}.${domain} 10800 IN A ${ip}"''
    ) nodes;
  
  # Generate PTR records from nodes  
  generatePTRRecords = domain: nodes:
    lib.mapAttrsToList (name: ip:
      ''"${ip} ${name}.${domain}"''
    ) nodes;

in {
  # Unbound recursive DNS server
  services.unbound = {
    enable = true;
    
    settings = {
      server = {
        # Listen on Nebula and local interfaces
        interface = [
          "127.0.0.1"
          "::1"
          "10.100.0.40"  # Rich-evans Nebula interface
          "192.168.68.200"  # Rich-evans LAN IP (static, high range)
        ];
        
        # Allow queries from Nebula network and local
        access-control = [
          "127.0.0.0/8 allow"
          "::1/128 allow"
          "10.100.0.0/16 allow"  # Nebula network
          "192.168.68.0/24 allow"  # Current LAN subnet
        ];
        
        # Security settings
        hide-identity = true;
        hide-version = true;
        qname-minimisation = true;
        
        # Performance
        num-threads = 4;
        msg-cache-size = "256M";
        rrset-cache-size = "512M";
        
        # DNSSEC validation
        auto-trust-anchor-file = "/var/lib/unbound/root.key";
        
        # Static host entries - generated from our node definitions
        local-data = 
          (generateARecords "nebula" nebulaNodes) ++
          (generateARecords "local" localNodes) ++
          [
            # Additional custom entries for future services
            # Will add kimb.dev entries once domain is set up with Caddy
          ];
        
        # Reverse DNS - generated from our node definitions
        local-data-ptr = 
          (generatePTRRecords "nebula" nebulaNodes) ++
          (generatePTRRecords "local" localNodes);
      };
      
      # Forward zones (optional - for specific domains)
      # forward-zone = [
      #   {
      #     name = ".";
      #     forward-addr = [
      #       "1.1.1.1@853#cloudflare-dns.com"  # DNS over TLS
      #       "1.0.0.1@853#cloudflare-dns.com"
      #     ];
      #   }
      # ];
    };
  };
  
  # Alternative: CoreDNS (more modern, plugin-based)
  # services.coredns = {
  #   enable = true;
  #   config = ''
  #     nebula:53 {
  #       hosts {
  #         10.100.0.1 lighthouse.nebula
  #         10.100.0.40 rich-evans.nebula
  #         10.100.0.3 bartleby.nebula
  #         10.100.0.4 marshmallow.nebula
  #         10.100.0.5 historian.nebula
  #         10.100.0.6 total-eclipse.nebula
  #         fallthrough
  #       }
  #       forward . 1.1.1.1 1.0.0.1
  #       cache 30
  #       log
  #     }
  #   '';
  # };
  
  # Open firewall for DNS
  networking.firewall = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };
}