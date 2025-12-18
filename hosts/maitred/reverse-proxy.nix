# Reverse proxy container - routes to containers or bridge (socat handles nebula)
# Also joins containernet as the Caddy bridge for container service mesh
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
  registry = import ../nebula-registry.nix;

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
  # Agenix secrets for containernet certs (bind-mounted into container)
  age.secrets = lib.mkIf cfg.services.reverse-proxy.enable {
    containernet-reverse-proxy-ca = {
      file = ../../secrets/containernet-ca-cert.age;
      path = "/etc/containernet-proxy/ca.crt";
      mode = "0644";
    };
    containernet-reverse-proxy-cert = {
      file = ../../secrets/containernet-reverse-proxy-cert.age;
      path = "/etc/containernet-proxy/cert.crt";
      mode = "0644";
    };
    containernet-reverse-proxy-key = {
      file = ../../secrets/containernet-reverse-proxy-key.age;
      path = "/etc/containernet-proxy/cert.key";
      mode = "0600";
    };
  };

  # Only create reverse proxy if enabled
  containers.reverse-proxy = lib.mkIf cfg.services.reverse-proxy.enable {
    autoStart = true;
    privateNetwork = true;
    hostAddress = cfg.networks.containerBridge;
    localAddress = cfg.services.reverse-proxy.containerIP;

    # Bind-mount containernet certs from host
    bindMounts = {
      "/etc/containernet/ca.crt" = {
        hostPath = config.age.secrets.containernet-reverse-proxy-ca.path;
        isReadOnly = true;
      };
      "/etc/containernet/cert.crt" = {
        hostPath = config.age.secrets.containernet-reverse-proxy-cert.path;
        isReadOnly = true;
      };
      "/etc/containernet/cert.key" = {
        hostPath = config.age.secrets.containernet-reverse-proxy-key.path;
        isReadOnly = true;
      };
    };

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
      environment.etc."resolv.conf".text = ''
        nameserver ${cfg.networks.containerBridge}
      '';

      services.caddy = {
        enable = true;
        inherit (cfg.admin) email;

        virtualHosts =
          serviceVirtualHosts
          // {
            # Root domain points to blog
            ${cfg.domain} = lib.mkIf cfg.services.blog.enable {
              extraConfig = ''
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

      # Containernet nebula for container service mesh
      environment.systemPackages = [pkgs.nebula];

      # Containernet config - lighthouse is maitred (10.102.0.1) reachable via container bridge
      environment.etc."containernet/config.yml".text = let
        lighthouseIp = builtins.head registry.networks.containernet.lighthouses;
      in ''
        pki:
          ca: /etc/containernet/ca.crt
          cert: /etc/containernet/cert.crt
          key: /etc/containernet/cert.key
        static_host_map:
          "${lighthouseIp}": ["${cfg.networks.containerBridge}:${toString registry.networks.containernet.port}"]
        lighthouse:
          hosts: ["${lighthouseIp}"]
        listen:
          port: 0
        tun:
          dev: nebula-cnt
        punchy:
          punch: true
          respond: true
        relay:
          use_relays: true
        firewall:
          outbound:
            - port: any
              proto: any
              host: any
          inbound:
            - port: any
              proto: icmp
              host: any
            - port: 80
              proto: tcp
              host: any
            - port: 443
              proto: tcp
              host: any
      '';

      systemd.services.nebula-containernet = {
        description = "Nebula containernet for reverse-proxy";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          ExecStart = "${pkgs.nebula}/bin/nebula -config /etc/containernet/config.yml";
          Restart = "always";
          RestartSec = "5s";
        };
      };

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
