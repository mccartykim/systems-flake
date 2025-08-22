# Monitoring configuration for maitred router
# Prometheus, Grafana, and metrics collection
{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.agenix.nixosModules.default
  ];

  # Prometheus monitoring server
  services.prometheus = {
    enable = true;
    port = 9090;
    listenAddress = "0.0.0.0"; # Listen on all interfaces for container access

    # Retention and storage
    retentionTime = "30d";

    # Scrape configuration
    scrapeConfigs = [
      # System metrics from node exporter
      {
        job_name = "maitred-node";
        static_configs = [
          {
            targets = ["localhost:9100"];
            labels = {
              instance = "maitred";
              role = "router";
            };
          }
        ];
        scrape_interval = "15s";
      }

      # Caddy metrics from reverse-proxy container
      {
        job_name = "caddy";
        static_configs = [
          {
            targets = ["192.168.100.2:2019"];
            labels = {
              instance = "reverse-proxy";
              service = "caddy";
            };
          }
        ];
        scrape_interval = "15s";
      }

      # Self-scraping for Prometheus health
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = ["localhost:9090"];
          }
        ];
      }
    ];

    # Alertmanager rules (basic)
    ruleFiles = [
      (pkgs.writeText "maitred.rules" ''
        groups:
          - name: maitred.rules
            rules:
              - alert: HighCPUUsage
                expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "High CPU usage on {{ $labels.instance }}"

              - alert: HighMemoryUsage
                expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "High memory usage on {{ $labels.instance }}"

              - alert: CaddyDown
                expr: up{job="caddy"} == 0
                for: 2m
                labels:
                  severity: critical
                annotations:
                  summary: "Caddy reverse proxy is down"
      '')
    ];
  };

  # Grafana dashboard server
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
        domain = "monitoring.kimb.dev";
        root_url = "https://monitoring.kimb.dev/";
      };

      security = {
        admin_user = "admin";
        admin_password = "admin"; # Change this after first login
      };

      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
    };

    provision = {
      enable = true;

      # Data sources
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://localhost:9090";
          isDefault = true;
        }
      ];

      # Dashboard provisioning
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

  # No additional firewall rules needed - accessed via reverse-proxy container

  # Create dashboard directory and populate with community dashboards
  systemd.tmpfiles.rules = [
    "d /var/lib/grafana/dashboards 0755 grafana grafana"
  ];
}
