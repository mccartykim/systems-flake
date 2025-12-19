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
        # Bind to dummy-cnt IP so responses have correct source
        listenHost = "192.168.100.254";
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

  # Dedicated IP on dummy interface for containernet lighthouse binding
  # Uses .254 to avoid conflict with reverse-proxy container's hostAddress (.1)
  # NOTE: Must use systemd.network.netdevs for Kind=dummy (not networking.interfaces.*.virtual which creates tap)
  systemd.network.netdevs."40-dummy-cnt" = {
    netdevConfig = {
      Name = "dummy-cnt";
      Kind = "dummy";
    };
  };

  systemd.network.networks."40-dummy-cnt" = {
    matchConfig.Name = "dummy-cnt";
    linkConfig.RequiredForOnline = "no";
    networkConfig.DHCP = "no";
    address = ["192.168.100.254/32"];
  };

  # Ensure containernet nebula waits for the dummy interface IP to be ready
  systemd.services."nebula@containernet" = {
    after = ["systemd-networkd.service" "sys-subsystem-net-devices-dummy\\x2dcnt.device"];
    wants = ["sys-subsystem-net-devices-dummy\\x2dcnt.device"];
    # Wait for actual IP assignment (up to 15s), not just device existence
    serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-dummy-ip" ''
      for i in $(seq 1 30); do
        if ${pkgs.iproute2}/bin/ip addr show dummy-cnt 2>/dev/null | grep -q "192.168.100.254"; then
          exit 0
        fi
        sleep 0.5
      done
      echo "ERROR: dummy-cnt never got IP 192.168.100.254 after 15s"
      exit 1
    '';
  };

  # Disable rp_filter on dummy-cnt to allow asymmetric routing from containers
  boot.kernel.sysctl."net.ipv4.conf.dummy-cnt.rp_filter" = 0;

  # Configure unbound to serve DNS on the dummy-cnt IP
  # This ensures containers get DNS responses from the IP they queried
  services.unbound = {
    enable = true;
    settings = {
      server = {
        # Listen on dummy-cnt for container DNS
        interface = ["192.168.100.254" "127.0.0.1" "::1"];
        # Allow queries from containers and local networks
        access-control = [
          "127.0.0.0/8 allow"
          "192.168.69.0/24 allow"
          "192.168.100.0/24 allow"
          "10.100.0.0/16 allow"
        ];
        # ip-transparent allows binding to addresses not yet configured
        ip-transparent = true;
      };
    };
  };
}
