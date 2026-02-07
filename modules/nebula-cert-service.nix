# Dynamic Nebula cert signing service
# Runs on a host with the CA key, signs short-lived certs for mesh hosts.
# Hosts authenticate with bearer tokens; the service looks up the host's
# IP and groups from the registry and signs a cert.
#
# Usage: Import this module on the host that will run the signing service
# (e.g., maitred), configure tokenHashes, and ensure the CA key secret
# (nebula-ca-key.age) is populated.
#
# Generate token hashes: echo -n "your-secret-token" | sha256sum | cut -d' ' -f1
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.certService;
  registry = import ../hosts/nebula-registry.nix;

  # Extract subnet mask from registry (e.g., "16" from "10.100.0.0/16")
  subnetMask = let
    parts = splitString "/" registry.networks.nebula.subnet;
  in
    elemAt parts 1;

  # Build HOSTS_CONFIG: sha256(token) -> {name, ip, groups}
  # Token hashes are stored in NixOS config (safe - only hashes, not tokens)
  # The actual token is only on the client (in agenix)
  hostsConfigJson = builtins.toJSON (
    listToAttrs (mapAttrsToList (hostname: tokenHash:
      nameValuePair tokenHash {
        name = hostname;
        ip = "${registry.nodes.${hostname}.ip}/${subnetMask}";
        groups = registry.nodes.${hostname}.groups or [];
      })
    cfg.tokenHashes)
  );
in {
  options.kimb.certService = {
    enable = mkEnableOption "Nebula dynamic cert signing service";

    port = mkOption {
      type = types.int;
      default = 8445;
      description = "Port for the signing service to listen on";
    };

    certDuration = mkOption {
      type = types.str;
      default = "48h";
      description = "Certificate validity duration";
    };

    tokenHashes = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = ''
        Map of hostname to sha256(bearer_token).
        The signing service uses these to authenticate requests and
        look up the host's IP/groups from the registry.

        Generate a token and its hash:
          TOKEN=$(openssl rand -hex 32)
          echo "Token: $TOKEN"
          echo -n "$TOKEN" | sha256sum | cut -d' ' -f1
      '';
      example = {
        historian = "a1b2c3d4e5f6...";
        marshmallow = "f6e5d4c3b2a1...";
      };
    };
  };

  config = mkIf cfg.enable {
    # Dedicated user for the signing service
    users.users.nebula-signing = {
      isSystemUser = true;
      group = "nebula-signing";
      description = "Nebula cert signing service";
    };
    users.groups.nebula-signing = {};

    # CA cert and key from agenix
    age.secrets.nebula-signing-ca-cert = {
      file = ../secrets/nebula-ca.age;
      path = "/etc/nebula-signing/ca.crt";
      owner = "nebula-signing";
      group = "nebula-signing";
      mode = "0444";
    };

    age.secrets.nebula-signing-ca-key = {
      file = ../secrets/nebula-ca-key.age;
      path = "/etc/nebula-signing/ca.key";
      owner = "nebula-signing";
      group = "nebula-signing";
      mode = "0400";
    };

    # Signing service
    systemd.services.nebula-signing-service = {
      description = "Nebula dynamic cert signing service";
      after = ["network.target" "agenix.service"];
      wants = ["agenix.service"];
      wantedBy = ["multi-user.target"];

      path = [pkgs.nebula];

      environment = {
        HOSTS_CONFIG = hostsConfigJson;
        CA_CERT = config.age.secrets.nebula-signing-ca-cert.path;
        CA_KEY = config.age.secrets.nebula-signing-ca-key.path;
        PORT = toString cfg.port;
        CERT_DURATION = cfg.certDuration;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${../packages/nebula-signing-service/signing-service.py}";
        Restart = "always";
        RestartSec = "5";
        User = "nebula-signing";
        Group = "nebula-signing";

        # Security hardening
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };
  };
}
