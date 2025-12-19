# Consolidated Nebula mesh configuration with agenix secrets
# Certificates are generated via `nix run .#generate-nebula-certs` (requires YubiKey)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.nebula;
  hostname = config.networking.hostName;
  registry = import ../hosts/nebula-registry.nix;

  # This host's config from registry
  hostConfig = registry.nodes.${hostname} or {};
  isLighthouse = hostConfig.isLighthouse or false;
  isRelay = hostConfig.isRelay or false;
  myIp = hostConfig.ip or "";

  # Helper: get IPs from node list, excluding our own
  getOtherIps = nodes: filter (ip: ip != myIp) (map (n: n.ip) nodes);

  # Lighthouses and relays from registry
  allLighthouses =
    filter (n: (n.isLighthouse or false) && n ? external)
    (attrValues registry.nodes);
  allRelays = filter (n: n.isRelay or false) (attrValues registry.nodes);

  # Derived config: exclude self from lighthouse/relay lists
  lighthouseIps =
    if isLighthouse
    then []
    else map (n: n.ip) allLighthouses;
  staticHosts = listToAttrs (map (n: nameValuePair n.ip [n.external]) allLighthouses);
  relayIps = getOtherIps allRelays;
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

  config = mkIf cfg.enable {
    # Agenix secrets for Nebula (file-based, generated via standalone script)
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
      inherit isLighthouse;

      ca = config.age.secrets.nebula-ca.path;
      cert = config.age.secrets.nebula-cert.path;
      key = config.age.secrets.nebula-key.path;

      lighthouses = lighthouseIps;
      staticHostMap = staticHosts;

      settings = {
        punchy = {
          punch = true;
          respond = true;
        };

        # Prefer direct LAN connections over relay/lighthouse routing
        local_range = registry.networks.lan.subnet;
        preferred_ranges = [registry.networks.lan.subnet];

        relay = {
          relays = relayIps;
          am_relay = isRelay; # Independent of lighthouse status
          use_relays = true;
        };

        # Periodic LAN route checking (helps mobile devices rediscover LAN)
        routines = {
          local_range_check_interval = 30; # Check every 30 seconds (0 = disabled)
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
          # Note: separate rules for OR logic (groups = AND, multiple rules = OR)
          ++ optionals cfg.openToPersonalDevices [
            {
              port = "any";
              proto = "any";
              group = "desktops";
            }
            {
              port = "any";
              proto = "any";
              group = "laptops";
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
