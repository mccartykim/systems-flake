# Consolidated Nebula mesh configuration. One place for everything
# kimb-specific: registry-derived topology, agenix-encrypted CA + per-
# host cert/key, host firewall opening, and the
# `openToPersonalDevices` shorthand for opening all ports to phones,
# laptops, and desktops at once.
#
# Certificates are generated via `nix run .#generate-nebula-certs`
# (requires YubiKey).
#
# Talks directly to nixpkgs's `services.nebula.networks.<name>` —
# previously this went through a thin nebula-node-flake wrapper, but
# that flake just baked in defaults that nixpkgs already exposes via
# `settings`, so we inline them here instead.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kimb.nebula;
  hostname = config.networking.hostName;
  registry = import ../hosts/nebula-registry.nix;

  hostConfig = registry.nodes.${hostname} or {};
  isLighthouse = hostConfig.isLighthouse or false;
  isRelay = hostConfig.isRelay or false;
  myIp = hostConfig.ip or "";

  getOtherIps = nodes: filter (ip: ip != myIp) (map (n: n.ip) nodes);

  allLighthouses =
    filter (n: (n.isLighthouse or false) && n ? external)
    (attrValues registry.nodes);
  allRelays = filter (n: n.isRelay or false) (attrValues registry.nodes);

  # Lighthouses don't register with themselves.
  lighthouseIps =
    if isLighthouse
    then []
    else map (n: n.ip) allLighthouses;

  # Include LAN address alongside the public endpoint so nebula can
  # bootstrap without DNS — avoids chicken-and-egg when maitred IS the
  # DNS server but also a lighthouse.
  staticHosts = listToAttrs (map (n:
    nameValuePair n.ip (
      [n.external] ++ optional (n ? lanIp) "${n.lanIp}:4242"
    ))
    allLighthouses);

  relayIps = getOtherIps allRelays;

  personalDevicesRules = optionals cfg.openToPersonalDevices [
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
    {
      port = "any";
      proto = "any";
      group = "mobile";
    }
  ];
in {
  options.kimb.nebula = {
    enable = mkEnableOption "Nebula mesh network with kimb registry-derived config";

    extraInboundRules = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "Additional inbound firewall rules for this host.";
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
      description = "Allow all ports from desktops, laptops, and mobile groups.";
    };
  };

  config = mkIf cfg.enable {
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
        routines.local_range_check_interval = 30; # 0 disables

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
          # Optional: open all ports to personal devices.
          # Note: separate rules for OR logic (groups within one rule
          # are AND; multiple rules are OR).
          ++ personalDevicesRules
          # Host-specific rules
          ++ cfg.extraInboundRules;
      };
    };

    # Ensure Nebula starts after agenix-decrypted certs are in place.
    # `wants` not `requires` so a misconfigured agenix doesn't take
    # nebula down with it.
    systemd.services."nebula@mesh" = {
      after = ["agenix.service"];
      wants = ["agenix.service"];
    };

    # Open the host firewall for Nebula. We open 4242 unconditionally —
    # nixpkgs's services.nebula picks 4242 for lighthouses/relays and
    # 0 (random) for workers, so this is only load-bearing on the
    # former, but harmless on the latter.
    networking.firewall.allowedUDPPorts = [4242];
  };
}
