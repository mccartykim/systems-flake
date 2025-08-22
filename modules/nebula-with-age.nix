# Enhanced Nebula module with age secret support
{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.nebula-mesh;
  nebulaSecrets = import ../secrets/nebula-secrets.nix;

  # Helper to get node config from secrets
  nodeConfig = nebulaSecrets.nodes.${config.networking.hostName} or null;
in {
  imports = [./nebula-mesh.nix];

  config = mkIf (cfg.enable && nodeConfig != null) {
    # Auto-configure based on hostname
    services.nebula-mesh = {
      hostIP = mkDefault nodeConfig.hostIP;
      groups = mkDefault nodeConfig.groups;
      lighthouses = mkDefault nebulaSecrets.lighthouses;
    };

    # Age secrets configuration
    age.secrets = mkIf (cfg.ageSecretsFile != null) {
      nebula-ca = {
        file = ../secrets/ca.crt.age;
        path = "${cfg.certificatesDir}/ca.crt";
        owner = "nebula-mesh";
        group = "nebula-mesh";
      };

      nebula-cert = {
        file = ../secrets/${config.networking.hostName}.crt.age;
        path = "${cfg.certificatesDir}/${config.networking.hostName}.crt";
        owner = "nebula-mesh";
        group = "nebula-mesh";
      };

      nebula-key = {
        file = ../secrets/${config.networking.hostName}.key.age;
        path = "${cfg.certificatesDir}/${config.networking.hostName}.key";
        owner = "nebula-mesh";
        group = "nebula-mesh";
        mode = "0600";
      };
    };

    # Ensure nebula starts after age secrets are decrypted
    systemd.services."nebula@mesh" = mkIf (cfg.ageSecretsFile != null) {
      after = ["agenix.service"];
      requires = ["agenix.service"];
    };
  };
}
