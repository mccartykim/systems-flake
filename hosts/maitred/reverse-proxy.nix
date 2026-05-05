# Reverse proxy container - routes to containers or bridge (socat handles nebula)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;

  # Generate Caddy virtual host for a service
  mkServiceVirtualHost = serviceName: service: let
    domain = "${service.subdomain}.${cfg.domain}";
    needsAuth = service.auth == "authelia";
    needsWebsockets = service.websockets;

    # Determine target IP: container IP or bridge (socat forwards remote hosts)
    targetIP =
      if service.containerIP != null
      then service.containerIP
      else cfg.networks.containerBridge;

    authConfig = lib.optionalString needsAuth ''
      forward_auth ${cfg.networks.containerBridge}:${toString cfg.services.authelia.port} {
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
  in
    lib.nameValuePair domain {
      extraConfig = ''
        ${authConfig}
        ${websocketConfig}
        reverse_proxy ${targetIP}:${toString service.port}
      '';
    };

  # Generate virtual hosts for all enabled public services (except reverse-proxy itself)
  serviceVirtualHosts = lib.mapAttrs' mkServiceVirtualHost (
    lib.filterAttrs (
      name: service:
        service.enable
        && service.publicAccess
        && name != "reverse-proxy"
    )
    cfg.services
  );
in {
  # Only create reverse proxy if enabled
  containers.reverse-proxy = lib.mkIf cfg.services.reverse-proxy.enable {
    autoStart = true;
    privateNetwork = true;
    hostAddress = cfg.networks.containerBridge;
    localAddress = cfg.services.reverse-proxy.containerIP;

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # Use host's DNS server (unbound on router)
      networking.nameservers = [cfg.networks.containerBridge];
      # Disable nsncd to prevent localhost DNS resolution
      services.nscd.enable = false;
      system.nssModules = lib.mkForce [];
      # Force resolv.conf to use host DNS
      networking.resolvconf.enable = false;
      environment.etc."resolv.conf".text = ''
        nameserver ${cfg.networks.containerBridge}
      '';

      services.caddy = {
        enable = true;
        inherit (cfg.admin) email;

        virtualHosts =
          serviceVirtualHosts
          // {
            # Root domain points to blog + Matrix .well-known delegation
            ${cfg.domain} = lib.mkIf cfg.services.blog.enable {
              extraConfig = ''
                # Matrix .well-known delegation (server_name = kimb.dev, actual server = matrix.kimb.dev)
                handle /.well-known/matrix/server {
                  header Content-Type application/json
                  respond `{"m.server": "matrix.${cfg.domain}:443"}`
                }
                handle /.well-known/matrix/client {
                  header Content-Type application/json
                  header Access-Control-Allow-Origin *
                  respond `{"m.homeserver":{"base_url":"https://matrix.${cfg.domain}"}}`
                }
                # Blog (default handler)
                reverse_proxy ${cfg.services.blog.containerIP}:${toString cfg.services.blog.port}
              '';
            };

            # Robot vacuum (Valetudo) - protected by Authelia
            "vacuum.${cfg.domain}" = {
              extraConfig = ''
                forward_auth ${cfg.networks.containerBridge}:${toString cfg.services.authelia.port} {
                  uri /api/verify?rd=https://auth.${cfg.domain}
                  copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
                }
                reverse_proxy 192.168.69.177:80
              '';
            };
          };
      };

      networking.firewall.allowedTCPPorts = [80 443 2019];

      system.stateVersion = "24.11";
    };
  };

  # NAT port forwarding for HTTP/HTTPS traffic
  networking.nat.forwardPorts = lib.mkIf cfg.services.reverse-proxy.enable [
    {
      sourcePort = 80;
      destination = "${cfg.services.reverse-proxy.containerIP}:80";
      proto = "tcp";
    }
    {
      sourcePort = 443;
      destination = "${cfg.services.reverse-proxy.containerIP}:443";
      proto = "tcp";
    }
  ];
}
