# Nebula configuration for marshmallow with agenix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.agenix.nixosModules.default
  ];

  # Agenix secrets for Nebula
  age.secrets = {
    nebula-ca = {
      file = ../../secrets/nebula-ca.age;
      path = "/etc/nebula/ca.crt";
      owner = "nebula-mesh";
      group = "nebula-mesh";
      mode = "0644";
    };

    nebula-cert = {
      file = ../../secrets/nebula-marshmallow-cert.age;
      path = "/etc/nebula/marshmallow.crt";
      owner = "nebula-mesh";
      group = "nebula-mesh";
      mode = "0644";
    };

    nebula-key = {
      file = ../../secrets/nebula-marshmallow-key.age;
      path = "/etc/nebula/marshmallow.key";
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

    lighthouses = ["10.100.0.1"];
    staticHostMap = {
      "10.100.0.1" = ["35.222.40.201:4242"];
    };

    settings = {
      punchy = {
        punch = true;
      };

      relay = {
        relays = ["10.100.0.1"];
        am_relay = false;
        use_relays = true;
      };

      tun = {
        disabled = false;
        dev = "nebula1";
      };

      logging = {
        level = "info";
      };
    };

    firewall = {
      outbound = [
        {
          port = "any";
          proto = "any";
          host = "any";
        }
      ];

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

  # Ensure Nebula starts after agenix
  systemd.services."nebula@mesh" = {
    after = ["agenix.service"];
    wants = ["agenix.service"];
  };

  # Open firewall for Nebula
  networking.firewall.allowedUDPPorts = [4242];
}
