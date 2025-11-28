# Consolidated Nebula mesh configuration with agenix
# Replaces per-host nebula.nix files
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.kimb.nebula;
  hostname = config.networking.hostName;
  registry = import ../hosts/nebula-registry.nix;
in {
  options.kimb.nebula = {
    enable = mkEnableOption "Nebula mesh network with agenix secrets";

    extraInboundRules = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "Additional inbound firewall rules for this host";
      example = [
        {
          port = 8080;
          proto = "tcp";
          host = "any";
        }
      ];
    };

    openToPersonalDevices = mkOption {
      type = types.bool;
      default = false;
      description = "Allow all ports from desktops and laptops groups";
    };
  };

  imports = [
    inputs.agenix.nixosModules.default
  ];

  config = mkIf cfg.enable {
    # Configure agenix to use SSH host key
    age.identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    # Agenix secrets for Nebula
    age.secrets = {
      nebula-ca = {
        file = ../secrets/nebula-ca.age;
        path = "/etc/nebula/ca.crt";
        owner = "nebula-mesh";
        group = "nebula-mesh";
        mode = "0644";
      };

      nebula-cert = {
        file = ../secrets/nebula-${hostname}-cert.age;
        path = "/etc/nebula/${hostname}.crt";
        owner = "nebula-mesh";
        group = "nebula-mesh";
        mode = "0644";
      };

      nebula-key = {
        file = ../secrets/nebula-${hostname}-key.age;
        path = "/etc/nebula/${hostname}.key";
        owner = "nebula-mesh";
        group = "nebula-mesh";
        mode = "0600";
      };
    };

    # Nebula mesh network
    services.nebula.networks.mesh = {
      enable = true;
      isLighthouse = false;

      ca = config.age.secrets.nebula-ca.path;
      cert = config.age.secrets.nebula-cert.path;
      key = config.age.secrets.nebula-key.path;

      lighthouses = [registry.network.lighthouse.ip];
      staticHostMap = {
        "${registry.network.lighthouse.ip}" = [registry.network.lighthouse.external];
      };

      settings = {
        punchy = {
          punch = true;
          respond = true;
        };

        # Prefer direct LAN connections over relay/lighthouse routing
        local_range = registry.network.lan.subnet;
        preferred_ranges = [registry.network.lan.subnet];

        relay = {
          relays = [registry.network.lighthouse.ip];
          am_relay = false;
          use_relays = true;
        };

        tun = {
          disabled = false;
          dev = "nebula1";
        };

        logging.level = "info";
      };

      firewall = {
        outbound = [
          {
            port = "any";
            proto = "any";
            host = "any";
          }
        ];

        inbound =
          [
            # ICMP from anywhere
            {
              port = "any";
              proto = "icmp";
              host = "any";
            }
            # SSH from anywhere
            {
              port = 22;
              proto = "tcp";
              host = "any";
            }
          ]
          # Optional: open all ports to personal devices
          ++ optionals cfg.openToPersonalDevices [
            {
              port = "any";
              proto = "any";
              groups = ["desktops" "laptops"];
            }
          ]
          # Host-specific rules
          ++ cfg.extraInboundRules;
      };
    };

    # Ensure Nebula starts after agenix
    systemd.services."nebula@mesh" = {
      after = ["agenix.service"];
      wants = ["agenix.service"];
    };

    # Open firewall for Nebula
    networking.firewall.allowedUDPPorts = [4242];
  };
}
