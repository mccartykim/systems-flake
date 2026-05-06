# Personalization layer for the nebula-node flake module.
# Reads hosts/nebula-registry.nix to compute lighthouses/relays/staticHostMap,
# manages agenix-encrypted CA + per-host cert/key (generated via
# `nix run .#generate-nebula-certs`), and exposes the kimb-specific
# `openToPersonalDevices` shorthand for opening all ports to phones,
# laptops, and desktops.
{
  config,
  lib,
  inputs,
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
  imports = [inputs.nebula-node.nixosModules.default];

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

    services.nebulaNode = {
      enable = true;
      inherit isLighthouse isRelay;
      ca = config.age.secrets.nebula-ca.path;
      cert = config.age.secrets.nebula-cert.path;
      key = config.age.secrets.nebula-key.path;
      lighthouses = lighthouseIps;
      staticHostMap = staticHosts;
      relays = relayIps;
      localRange = registry.networks.lan.subnet;
      preferredRanges = [registry.networks.lan.subnet];
      inbound =
        [
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
        ]
        ++ personalDevicesRules
        ++ cfg.extraInboundRules;
    };
  };
}
