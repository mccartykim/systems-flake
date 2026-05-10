# Observability NixOS Module
# Centralized node_exporter + journal-upload config for remote hosts
# that get scraped by Prometheus on maitred. Single source of truth
# for port number, collectors, and textfile directory path.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.observability;

  # Single source of truth for observability constants
  nodeExporterPort = 9100;
  journalRemotePort = 19532;
  textfileDir = "/var/lib/prometheus-node-exporter-textfiles";
  enabledCollectors = ["systemd" "processes"];

  registry = import ../hosts/nebula-registry.nix;
  maitredIp = registry.nodes.maitred.ip;
in {
  options.kimb.observability = {
    enable = mkEnableOption "observability stack (node_exporter + journal-upload)";
  };

  config = mkIf cfg.enable {
    # Node exporter for Prometheus scraping
    services.prometheus.exporters.node = {
      enable = true;
      port = nodeExporterPort;
      inherit enabledCollectors;
      listenAddress = "0.0.0.0";
      extraFlags = ["--collector.textfile.directory=${textfileDir}"];
    };

    # Forward journal to maitred for central aggregation
    systemd.services.systemd-journal-upload = {
      description = "Upload journal to maitred";
      after = ["network.target"];
      wants = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-journal-upload --url=http://${maitredIp}:${toString journalRemotePort}";
        User = "root";
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # Create textfile directory for node_exporter textfile collector
    systemd.tmpfiles.rules = [
      "d ${textfileDir} 0777 nobody nogroup -"
    ];

    # Open Nebula firewall for node_exporter scraping from maitred
    kimb.nebula.extraInboundRules = mkIf config.kimb.nebula.enable [
      {
        port = nodeExporterPort;
        proto = "tcp";
        host = "maitred";
      }
    ];
  };
}
