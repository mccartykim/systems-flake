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
      # Configure DNS for external certificate resolution - use router's DNS
      networking.nameservers = [ "192.168.69.1" ];
      services.resolved.enable = false;
      networking.resolvconf.enable = false;
      
      # Force specific DNS configuration with fallback
      environment.etc."resolv.conf".text = ''
        nameserver 192.168.69.1
        nameserver 8.8.8.8
        nameserver 8.8.4.4
        options edns0
      '';
      
      # Caddy for HTTPS termination and reverse proxy
      services.caddy = {
        enable = true;
        email = "mccartykim@zoho.com";
        
        
        
        # Enable metrics for monitoring
        globalConfig = ''
          servers {
            metrics
          }
        '';
        
        virtualHosts = {
          # External domains (Let's Encrypt certificates)
          "kimb.dev" = {
            extraConfig = ''
              reverse_proxy 192.168.100.3:8080
            '';
          };
          "blog.kimb.dev" = {
            extraConfig = ''
              reverse_proxy 192.168.100.3:8080
            '';
          };
          "auth.kimb.dev" = {
            extraConfig = ''
              reverse_proxy 192.168.100.4:9091
            '';
          };
          "home.kimb.dev" = {
            extraConfig = ''
              forward_auth 192.168.100.4:9091 {
                uri /api/verify?rd=https://auth.kimb.dev
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
              }
              reverse_proxy 192.168.100.1:8082 {
                header_up Host 192.168.100.1:8082
              }
            '';
          };
          "http://home.kimb.dev" = {
            extraConfig = ''
              forward_auth 192.168.100.4:9091 {
                uri /api/verify?rd=https://auth.kimb.dev
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
              }
              reverse_proxy 192.168.100.1:8082 {
                header_up Host 192.168.100.1:8082
              }
            '';
          };
          "grafana.kimb.dev" = {
            extraConfig = ''
              forward_auth 192.168.100.4:9091 {
                uri /api/verify?rd=https://auth.kimb.dev
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
              }
              reverse_proxy 192.168.100.1:3000
            '';
          };
          "http://grafana.kimb.dev" = {
            extraConfig = ''
              forward_auth 192.168.100.4:9091 {
                uri /api/verify?rd=https://auth.kimb.dev
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
              }
              reverse_proxy 192.168.100.1:3000
            '';
          };
          "prometheus.kimb.dev" = {
            extraConfig = ''
              forward_auth 192.168.100.4:9091 {
                uri /api/verify?rd=https://auth.kimb.dev
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
              }
              reverse_proxy 192.168.100.1:9090
            '';
          };
          "http://prometheus.kimb.dev" = {
            extraConfig = ''
              forward_auth 192.168.100.4:9091 {
                uri /api/verify?rd=https://auth.kimb.dev
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
              }
              reverse_proxy 192.168.100.1:9090
            '';
          };
          "copyparty.kimb.dev" = {
            extraConfig = ''
              forward_auth 192.168.100.4:9091 {
                uri /api/verify?rd=https://auth.kimb.dev
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
              }
              reverse_proxy 192.168.100.1:3923
            '';
          };
          "http://copyparty.kimb.dev" = {
            extraConfig = ''
              forward_auth 192.168.100.4:9091 {
                uri /api/verify?rd=https://auth.kimb.dev
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
              }
              reverse_proxy 192.168.100.1:3923
            '';
          };
        };
      };
      
      
      
      # Open firewall for HTTP/HTTPS and metrics
      networking.firewall.allowedTCPPorts = [ 80 443 2019 ];
      
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
    # HTTP from WAN
    {
      sourcePort = 80;
      destination = "192.168.100.2:80";
      proto = "tcp";
    }
    # HTTPS from WAN
    {
      sourcePort = 443;
      destination = "192.168.100.2:443";
      proto = "tcp";
    }
    # Hairpin NAT removed - using split-brain DNS instead
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
