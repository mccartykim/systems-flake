{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.services.nebula-mesh;
in
{
  options.services.nebula-mesh = {
    enable = mkEnableOption "Nebula mesh network";

    hostName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Name of this host in the Nebula mesh";
    };

    meshNetwork = mkOption {
      type = types.str;
      default = "10.100.0.0/16";
      description = "CIDR block for the mesh network";
    };

    hostIP = mkOption {
      type = types.str;
      description = "This host's IP address in the mesh network";
      example = "10.100.0.10";
    };

    groups = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Groups this host belongs to";
      example = [ "laptops" "nixos" ];
    };

    lighthouse = {
      enable = mkEnableOption "lighthouse mode";
      
      externalIP = mkOption {
        type = types.str;
        description = "External IP address of this lighthouse";
        example = "203.0.113.1";
      };

      port = mkOption {
        type = types.port;
        default = 4242;
        description = "Port for lighthouse to listen on";
      };
    };

    lighthouses = mkOption {
      type = types.listOf (types.submodule {
        options = {
          meshIP = mkOption {
            type = types.str;
            description = "Lighthouse's mesh IP address";
            example = "10.100.0.1";
          };
          
          publicEndpoints = mkOption {
            type = types.listOf types.str;
            description = "Public endpoints to reach this lighthouse";
            example = [ "203.0.113.1:4242" ];
          };
        };
      });
      default = [];
      description = "List of lighthouses to connect to";
    };

    certificatesDir = mkOption {
      type = types.str;
      default = "/etc/nebula";
      description = "Directory containing Nebula certificates";
    };

    extraSettings = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional Nebula configuration";
      example = {
        punchy = { punch = true; };
        logging = { level = "info"; };
      };
    };
  };

  config = mkIf cfg.enable {
    # Generate static host map from lighthouses
    services.nebula.networks.mesh = {
      enable = true;
      isLighthouse = cfg.lighthouse.enable;
      
      ca = "${cfg.certificatesDir}/ca.crt";
      cert = "${cfg.certificatesDir}/${cfg.hostName}.crt";
      key = "${cfg.certificatesDir}/${cfg.hostName}.key";

      lighthouses = mkIf (!cfg.lighthouse.enable) (map (lh: lh.meshIP) cfg.lighthouses);
      
      staticHostMap = mkIf (!cfg.lighthouse.enable) (
        listToAttrs (map (lh: {
          name = lh.meshIP;
          value = lh.publicEndpoints;
        }) cfg.lighthouses)
      );

      listen = mkIf cfg.lighthouse.enable {
        host = "0.0.0.0";
        port = cfg.lighthouse.port;
      };

      settings = recursiveUpdate {
        tun = {
          disabled = false;
          dev = "nebula1";
        };

        logging = {
          level = "info";
        };

        punchy = {
          punch = true;
        };

        relay = mkIf (!cfg.lighthouse.enable) {
          relays = map (lh: lh.meshIP) cfg.lighthouses;
          am_relay = false;
          use_relays = true;
        };
      } cfg.extraSettings;

      firewall = {
        outbound = [{
          port = "any";
          proto = "any";
          host = "any";
        }];

        inbound = [
          {
            port = "any";
            proto = "icmp";
            host = "any";
          }
          {
            port = 22;
            proto = "tcp";
            host = "any";
          }
        ];
      };
    };

    # Open firewall for Nebula
    networking.firewall.allowedUDPPorts = [ cfg.lighthouse.port ];

    # Ensure certificates directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.certificatesDir} 0755 root root -"
    ];

    # Add some helpful assertions
    assertions = [
      {
        assertion = cfg.lighthouse.enable -> (cfg.lighthouse.externalIP != "");
        message = "lighthouse.externalIP must be set when lighthouse mode is enabled";
      }
      {
        assertion = !cfg.lighthouse.enable -> (cfg.lighthouses != []);
        message = "At least one lighthouse must be configured for non-lighthouse nodes";
      }
    ];
  };
}