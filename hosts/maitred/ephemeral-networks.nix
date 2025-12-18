# Ephemeral nebula networks: buildnet + containernet
# Maitred serves as lighthouse for both hot CA networks
{
  config,
  lib,
  pkgs,
  ...
}: let
  registry = import ../nebula-registry.nix;
in {
  imports = [
    ../../modules/ephemeral-ca.nix
  ];

  kimb.ephemeralCA = {
    enable = true;

    networks = {
      buildnet = {
        subnet = registry.networks.buildnet.subnet;
        port = registry.networks.buildnet.port;
        lighthouseIp = registry.nodes.maitred.buildnetIp;
        # Peer with oracle for redundancy
        peerLighthouses = [{
          ip = registry.nodes.oracle.buildnetIp;
          external = "150.136.155.204:${toString registry.networks.buildnet.port}";
        }];
        poolStart = 100;
        poolEnd = 254;
        defaultDuration = "24h";
        defaultGroups = ["builders"];
        tunDevice = "nebula-build";
      };

      containernet = {
        subnet = registry.networks.containernet.subnet;
        port = registry.networks.containernet.port;
        lighthouseIp = registry.nodes.maitred.containernetIp;
        # Peer with oracle for redundancy
        peerLighthouses = [{
          ip = registry.nodes.oracle.containernetIp;
          external = "150.136.155.204:${toString registry.networks.containernet.port}";
        }];
        poolStart = 100;
        poolEnd = 254;
        defaultDuration = "168h"; # 1 week
        defaultGroups = ["containers"];
        tunDevice = "nebula-container";
      };
    };

    certService = {
      enable = true;
      port = 8444;
    };
  };

  # Expose cert service via Caddy (handled in reverse-proxy.nix)
  # Just open the internal port for localhost access
  networking.firewall.allowedTCPPorts = [8444];
}
