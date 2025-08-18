# Reverse proxy container configuration for maitred
# Handles HTTPS termination and routing to internal services
{ config, pkgs, inputs, ... }:

{
  # NixOS container for reverse proxy
  containers.reverse-proxy = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "192.168.100.1";      # Router's container bridge IP
    localAddress = "192.168.100.2";     # Proxy container IP
    
    config = { config, pkgs, ... }: {
      # Caddy for HTTPS termination and reverse proxy
      services.caddy = {
        enable = true;
        email = "mccartykim@zoho.com";
        virtualHosts = {
          "kimb.dev" = {
            extraConfig = ''
              reverse_proxy 192.168.100.3:8080
            '';
          };
        };
      };
      
      # Open firewall for HTTP/HTTPS
      networking.firewall.allowedTCPPorts = [ 80 443 ];
      
      # Minimal system packages
      environment.systemPackages = with pkgs; [
        curl
        htop
      ];
      
      system.stateVersion = "24.11";
    };
  };
  
  # Port forwarding from router to proxy container
  networking.nat.forwardPorts = [
    # HTTP
    {
      sourcePort = 80;
      destination = "192.168.100.2:80";
      proto = "tcp";
    }
    # HTTPS  
    {
      sourcePort = 443;
      destination = "192.168.100.2:443";
      proto = "tcp";
    }
  ];
  
  # Add container network to NAT for outbound internet access
  networking.nat.internalInterfaces = [ "ve-+" ];
  
  # Allow container bridge traffic
  networking.firewall = {
    trustedInterfaces = [ "ve-+" ];  # All container virtual ethernet interfaces
    extraCommands = ''
      # Allow traffic between containers
      iptables -A FORWARD -d 192.168.100.0/24 -j ACCEPT
      iptables -A FORWARD -s 192.168.100.0/24 -j ACCEPT
    '';
  };
}