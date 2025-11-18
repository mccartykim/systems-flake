# Migrated monitoring stack using kimb-services options
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
in {
  # Prometheus monitoring (host service)
  services.prometheus = lib.mkIf cfg.services.prometheus.enable {
    enable = true;
    port = cfg.services.prometheus.port;

    # Scrape configurations - map over enabled services
    scrapeConfigs = let
      # Helper to create scrape config for a service
      mkServiceScrapeConfig = name: service: {
        job_name = name;
        static_configs = [
          {
            targets = [
              (
                if service.host == "maitred" && !service.container
                then "localhost:${toString service.port}"
                else if service.host == "maitred" && service.container && name == "reverse-proxy"
                then "${cfg.networks.reverseProxyIP}:2019" # Caddy metrics
                else if service.host == "rich-evans"
                then "10.100.0.40:${toString service.port}"
                else "localhost:${toString service.port}"
              )
            ];
          }
        ];
      };

      # Get scrape configs for enabled services with metrics
      serviceScrapeConfigs = lib.mapAttrsToList mkServiceScrapeConfig (
        lib.filterAttrs (
          name: service:
            service.enable
            && (name == "prometheus" || name == "reverse-proxy") # Services that expose metrics
        )
        cfg.services
      );

      # Always include node exporter
      nodeExporterConfig = {
        job_name = "node-exporter";
        static_configs = [{targets = ["localhost:9100"];}];
      };
    in
      [nodeExporterConfig] ++ serviceScrapeConfigs;

    # Rules and alerting can be added here
    ruleFiles = [];

    # Retention policy
    extraFlags = [
      "--storage.tsdb.retention.time=90d"
      "--storage.tsdb.retention.size=10GB"
    ];

    # Node exporter configuration
    exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = ["systemd" "processes"];
      # Only listen on localhost and Nebula
      listenAddress = "0.0.0.0";
      openFirewall = false; # Manually control access
    };
  };

  # Grafana visualization (host service)
  services.grafana = lib.mkIf cfg.services.grafana.enable {
    enable = true;

    settings = {
      server = {
        http_port = cfg.services.grafana.port;
        http_addr = "0.0.0.0"; # Accept connections from reverse-proxy container
        domain = "${cfg.services.grafana.subdomain}.${cfg.domain}";
        root_url = "https://${cfg.services.grafana.subdomain}.${cfg.domain}";
      };

      security = {
        admin_user = cfg.admin.name;
        admin_password = "admin"; # TODO: Change default password
        secret_key = "$__file{/run/secrets/grafana-secret-key}";
      };

      database = {
        type = "sqlite3";
        path = "/var/lib/grafana/grafana.db";
      };

      analytics.reporting_enabled = false;
      users.allow_sign_up = false;
    };

    provision = lib.mkIf cfg.services.prometheus.enable {
      enable = true;

      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:${toString cfg.services.prometheus.port}";
          isDefault = true;
        }
      ];

      dashboards.settings.providers = [
        {
          name = "default";
          orgId = 1;
          folder = "";
          type = "file";
          disableDeletion = false;
          updateIntervalSeconds = 10;
          allowUiUpdates = true;
          options.path = "/var/lib/grafana/dashboards";
        }
      ];
    };
  };

  # Firewall rules for monitoring services
  networking.firewall = {
    interfaces = {
      # Allow monitoring services access from LAN and Nebula
      "br-lan".allowedTCPPorts = lib.flatten [
        (lib.optional cfg.services.grafana.enable cfg.services.grafana.port)
        (lib.optional cfg.services.prometheus.enable cfg.services.prometheus.port)
        [9100] # node exporter
      ];
      "nebula-kimb".allowedTCPPorts = lib.flatten [
        (lib.optional cfg.services.grafana.enable cfg.services.grafana.port)
        (lib.optional cfg.services.prometheus.enable cfg.services.prometheus.port)
        [9100] # node exporter
      ];
    };
  };
}
