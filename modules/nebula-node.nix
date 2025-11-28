# Consolidated Nebula mesh configuration with agenix
# Replaces per-host nebula.nix files
# Supports multiple lighthouses and per-host lighthouse/relay roles
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

  # Get this host's config from registry
  hostConfig = registry.nodes.${hostname} or {};

  # Is this host a lighthouse?
  isLighthouse = hostConfig.isLighthouse or false;

  # Is this host a relay?
  isRelay = hostConfig.isRelay or false;

  # For lighthouses: list other lighthouses (not self) in static_host_map
  # For regular nodes: list all lighthouses
  otherLighthouseIPs = filter (ip: ip != (hostConfig.ip or "")) registry.lighthouseIPs;
  otherLighthouseStaticHostMap = filterAttrs (ip: _: ip != (hostConfig.ip or "")) registry.lighthouseStaticHostMap;

  # Lighthouse hosts list: lighthouses list OTHER lighthouses, regular nodes list ALL
  lighthouseHosts =
    if isLighthouse
    then otherLighthouseIPs
    else registry.lighthouseIPs;

  # Static host map: lighthouses only need other lighthouses, regular nodes need all
  staticHostMap =
    if isLighthouse
    then otherLighthouseStaticHostMap
    else registry.lighthouseStaticHostMap;

  # Relays: use all relay IPs except self
  relayIPs = filter (ip: ip != (hostConfig.ip or "")) registry.relayIPs;
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
      inherit isLighthouse;

      ca = config.age.secrets.nebula-ca.path;
      cert = config.age.secrets.nebula-cert.path;
      key = config.age.secrets.nebula-key.path;

      # Lighthouses list other lighthouses; regular nodes list all lighthouses
      lighthouses = lighthouseHosts;
      inherit staticHostMap;

      settings =
        {
          punchy = {
            punch = true;
            respond = true;
          };

          # Prefer direct LAN connections over relay/lighthouse routing
          local_range = registry.networks.lan.subnet;
          preferred_ranges = [registry.networks.lan.subnet];

          relay = {
            # Use other relays (not self) for fallback routing
            relays = relayIPs;
            am_relay = isRelay;
            use_relays = true;
          };

          tun = {
            disabled = false;
            dev = "nebula1";
          };

          logging.level = "info";
        }
        # Lighthouses with dynamic IPs need to advertise their external address
        // optionalAttrs (isLighthouse && hostConfig ? external) {
          lighthouse.advertise_addrs = [hostConfig.external];
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
