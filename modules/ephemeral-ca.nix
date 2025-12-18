# Ephemeral CA management for hot nebula networks
# Manages buildnet and containernet with dynamic cert allocation
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.ephemeralCA;
  registry = import ../hosts/nebula-registry.nix;
in {
  options.kimb.ephemeralCA = {
    enable = mkEnableOption "Ephemeral CA management for hot networks";

    networks = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          subnet = mkOption {
            type = types.str;
            description = "Subnet for this network (e.g., 10.101.0.0/16)";
          };

          port = mkOption {
            type = types.int;
            description = "UDP port for nebula (different per network)";
          };

          lighthouseIp = mkOption {
            type = types.str;
            description = "IP address of this host on this network";
          };

          peerLighthouses = mkOption {
            type = types.listOf (types.submodule {
              options = {
                ip = mkOption {
                  type = types.str;
                  description = "Nebula IP of the peer lighthouse";
                };
                external = mkOption {
                  type = types.str;
                  description = "External endpoint (host:port) of the peer lighthouse";
                };
              };
            });
            default = [];
            description = "Other lighthouses to peer with for redundancy";
          };

          poolStart = mkOption {
            type = types.int;
            default = 100;
            description = "Start of dynamic IP allocation pool";
          };

          poolEnd = mkOption {
            type = types.int;
            default = 254;
            description = "End of dynamic IP allocation pool";
          };

          defaultDuration = mkOption {
            type = types.str;
            default = "24h";
            description = "Default certificate duration";
          };

          defaultGroups = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Default groups for allocated certificates";
          };

          tunDevice = mkOption {
            type = types.str;
            description = "Name of the tun device for this network";
          };
        };
      });
      default = {};
      description = "Ephemeral networks to manage";
    };

    certService = {
      enable = mkEnableOption "cert allocation service";

      port = mkOption {
        type = types.int;
        default = 8444;
        description = "Port for the cert service to listen on";
      };
    };
  };

  config = mkIf cfg.enable {
    # Open firewall for all ephemeral network ports
    networking.firewall.allowedUDPPorts = mapAttrsToList (name: net: net.port) cfg.networks;

    # Configure nebula lighthouse for each network
    services.nebula.networks = mapAttrs (name: net: {
      enable = true;
      isLighthouse = true;
      ca = config.age.secrets."${name}-ca-cert".path;
      cert = config.age.secrets."${name}-lighthouse-cert".path;
      key = config.age.secrets."${name}-lighthouse-key".path;
      listen.port = net.port;
      # Peer with other lighthouses for redundancy
      lighthouses = map (peer: peer.ip) net.peerLighthouses;
      staticHostMap = builtins.listToAttrs (map (peer: {
        name = peer.ip;
        value = [peer.external];
      }) net.peerLighthouses);
      settings = {
        tun.dev = net.tunDevice;
        firewall = {
          inbound = [
            {port = "any"; proto = "icmp"; host = "any";}
            # Allow cert service access from all hosts on this network
            {port = cfg.certService.port; proto = "tcp"; host = "any";}
          ];
          outbound = [
            {port = "any"; proto = "any"; host = "any";}
          ];
        };
      };
    }) cfg.networks;

    # Agenix secrets for each network's CA and lighthouse certs + cert service token
    age.secrets = mkMerge (
      # Network secrets
      (mapAttrsToList (name: net: {
        "${name}-ca-cert" = {
          file = ../secrets/${name}-ca-cert.age;
          path = "/etc/ephemeral-ca/${name}/ca.crt";
          mode = "0644";
        };
        "${name}-ca-key" = {
          file = ../secrets/${name}-ca-key.age;
          path = "/etc/ephemeral-ca/${name}/ca.key";
          mode = "0600";
        };
        "${name}-lighthouse-cert" = {
          file = ../secrets/${name}-lighthouse-cert.age;
          path = "/etc/ephemeral-ca/${name}/lighthouse.crt";
          mode = "0644";
        };
        "${name}-lighthouse-key" = {
          file = ../secrets/${name}-lighthouse-key.age;
          path = "/etc/ephemeral-ca/${name}/lighthouse.key";
          mode = "0400";
          owner = "nebula-${name}";
          group = "nebula-${name}";
        };
      }) cfg.networks)
      # Cert service token
      ++ (optional cfg.certService.enable {
        cert-service-token = {
          file = ../secrets/cert-service-token.age;
          path = "/etc/ephemeral-ca/token";
          mode = "0600";
        };
      })
    );

    # Cert allocation service
    systemd.services.ephemeral-cert-service = mkIf cfg.certService.enable {
      description = "Ephemeral Nebula cert allocation service";
      after = ["network.target" "agenix.service"];
      wantedBy = ["multi-user.target"];

      path = [ pkgs.nebula ];

      environment = {
        NETWORKS_CONFIG = builtins.toJSON (mapAttrs (name: net: {
          ca_cert = "/etc/ephemeral-ca/${name}/ca.crt";
          ca_key = "/etc/ephemeral-ca/${name}/ca.key";
          subnet = builtins.head (builtins.match "([0-9]+\\.[0-9]+\\.[0-9]+).*" net.lighthouseIp);
          pool_start = net.poolStart;
          pool_end = net.poolEnd;
          default_duration = net.defaultDuration;
          default_groups = net.defaultGroups;
        }) cfg.networks);
        PORT = toString cfg.certService.port;
        STATE_DIR = "/var/lib/ephemeral-certs";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${../packages/cert-service/cert-service.py}";
        Restart = "always";
        RestartSec = "5";
        StateDirectory = "ephemeral-certs";
        EnvironmentFile = config.age.secrets.cert-service-token.path;
      };
    };
  };
}
