# Reverse proxy — the a3j.8.2 migration of maitred's Caddy edge onto historian.
#
# Unlike maitred (Caddy in an nspawn on a private 192.168.100.x bridge, vhosts
# pointing at socat forwarders on containerBridge), this is a HOST service on
# historian (dom0) with the vhosts proxying the LOCAL services at 127.0.0.1.
# That is what lets the 9 socat forwarders on maitred dissolve at the flip.
#
# Staging: this file is gated on historian's OWN registry bucket, so adding it
# does NOT change maitred's behaviour (maitred still owns the public edge until
# the (b) flip). After the flip, the kimb.dev split-brain DNS + maitred's
# :80/:443 forwarding point here.
#
# Certs: Caddy's ACME state (Let's Encrypt/ZeroSSL accounts + 16 certs) is
# rsync'd from maitred's container root into /var/lib/caddy, so the moved certs
# serve immediately (no HTTP-01 challenge needed mid-move).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
  registry = import ../nebula-registry.nix;

  # Generate Caddy virtual host for a service. Local services proxy 127.0.0.1;
  # services still on another host (e.g. coach.kimb.dev on rich-evans until
  # a3j.7) proxy that host's Nebula IP directly (no socat hop).
  mkServiceVirtualHost = serviceName: service: let
    domain = "${service.subdomain}.${cfg.domain}";
    needsAuth = service.auth == "authelia";
    needsWebsockets = service.websockets;
    targetIP =
      if service.containerIP != null
      then service.containerIP
      else if service.host == "historian"
      then "127.0.0.1"
      else registry.nodes.${service.host}.ip or "127.0.0.1";

    authConfig = lib.optionalString needsAuth ''
      forward_auth ${targetIP}:${toString cfg.services.authelia.port} {
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
  services.caddy = lib.mkIf cfg.services.reverse-proxy.enable {
    enable = true;
    inherit (cfg.admin) email;

    virtualHosts =
      serviceVirtualHosts
      // {
        # knit.kimb.dev — hand-written 4-way split (parity with maitred's):
        # /api/* → BFF, /xrpc/* + /lexicons/* → AppView, else → the knit-web
        # nspawn container (nginx SPA shell).
        "knit.${cfg.domain}" = lib.mkIf cfg.services.knit.enable {
          extraConfig = ''
            handle /api/* {
              reverse_proxy 127.0.0.1:${toString cfg.services.knit-bff.port}
            }
            handle /xrpc/* {
              reverse_proxy 127.0.0.1:${toString cfg.services.knit.port}
            }
            handle /lexicons/* {
              reverse_proxy 127.0.0.1:${toString cfg.services.knit.port}
            }
            handle {
              reverse_proxy 127.0.0.1:${toString cfg.services.knit-web.port}
            }
          '';
        };

        # Root domain → blog + Matrix .well-known delegation.
        ${cfg.domain} = lib.mkIf cfg.services.blog.enable {
          extraConfig = ''
            handle /.well-known/matrix/server {
              header Content-Type application/json
              respond `{"m.server": "matrix.${cfg.domain}:443"}`
            }
            handle /.well-known/matrix/client {
              header Content-Type application/json
              header Access-Control-Allow-Origin *
              respond `{"m.homeserver":{"base_url":"https://matrix.${cfg.domain}"}}`
            }
            reverse_proxy 127.0.0.1:${toString cfg.services.blog.port}
          '';
        };

        # Robot vacuum (Valetudo, LAN IP) protected by Authelia.
        "vacuum.${cfg.domain}" = {
          extraConfig = ''
            forward_auth 127.0.0.1:${toString cfg.services.authelia.port} {
              uri /api/verify?rd=https://auth.${cfg.domain}
              copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
            }
            reverse_proxy 192.168.69.177:80
          '';
        };
      };

    # Caddy binds 80/443 on the host (host service, not a container).
    openFirewall = true;
  };
}
