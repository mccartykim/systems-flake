# Migrated reverse proxy using kimb-services options
{ config, lib, pkgs, ... }:

let
  cfg = config.kimb;
  
  # Generate Caddy virtual host for a service
  mkServiceVirtualHost = serviceName: service: let
    domain = "${service.subdomain}.${cfg.domain}";
    needsAuth = service.auth == "authelia";
    needsWebsockets = service.websockets;
    
    # Determine target IP based on host and container settings
    targetIP = 
      if service.host == "maitred" && service.container then
        # Container service on maitred - use container IP
        if serviceName == "blog" then "192.168.100.3"
        else if serviceName == "reverse-proxy" then "192.168.100.2"
        else "192.168.100.10"  # Default container IP
      else if service.host == "rich-evans" then
        "10.100.0.40"  # rich-evans Nebula IP
      else if service.host == "bartleby" then
        "10.100.0.30"  # bartleby Nebula IP
      else
        "127.0.0.1";   # localhost for maitred host services
    
    authConfig = lib.optionalString needsAuth ''
      forward_auth ${cfg.networks.reverseProxyIP}:${toString cfg.services.authelia.port} {
        uri /api/verify?rd=https://auth.${cfg.domain}
        copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
      }
    '';
    
    websocketConfig = lib.optionalString needsWebsockets ''
      @websockets {
        header Connection *Upgrade*
        header Upgrade websocket
      }
      reverse_proxy @websockets ${targetIP}:${toString service.port}
    '';
    
  in lib.nameValuePair domain {
    extraConfig = ''
      ${authConfig}
      ${websocketConfig}
      reverse_proxy ${targetIP}:${toString service.port}
    '';
  };
  
  # Generate virtual hosts for all enabled public services (except reverse-proxy itself)
  serviceVirtualHosts = lib.mapAttrs' mkServiceVirtualHost (
    lib.filterAttrs (name: service: 
      service.enable && 
      service.publicAccess && 
      name != "reverse-proxy"
    ) cfg.services
  );

in {
  # Only create reverse proxy if enabled
  containers.reverse-proxy = lib.mkIf cfg.services.reverse-proxy.enable {
    autoStart = true;
    privateNetwork = true;
    hostAddress = cfg.networks.containerBridge;
    localAddress = cfg.networks.reverseProxyIP;

    config = { config, pkgs, lib, ... }: {
      networking.nameservers = [ cfg.networks.containerBridge ];

      services.caddy = {
        enable = true;
        email = cfg.admin.email;

        virtualHosts = serviceVirtualHosts // {
          # Root domain points to blog
          ${cfg.domain} = lib.mkIf cfg.services.blog.enable {
            extraConfig = ''
              reverse_proxy 192.168.100.3:${toString cfg.services.blog.port}
            '';
          };
        };
      };

      networking.firewall.allowedTCPPorts = [ 80 443 2019 ];
      system.stateVersion = "24.11";
    };
  };

  # NAT port forwarding for HTTP/HTTPS traffic
  networking.nat.forwardPorts = lib.mkIf cfg.services.reverse-proxy.enable [
    {
      sourcePort = 80;
      destination = "${cfg.networks.reverseProxyIP}:80";
      proto = "tcp";
    }
    {
      sourcePort = 443;
      destination = "${cfg.networks.reverseProxyIP}:443";
      proto = "tcp";
    }
  ];
}