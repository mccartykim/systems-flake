# Monitoring stack with SRE observability (Phase 0)
# Prometheus + Grafana + Alertmanager + blackbox + journal-remote
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
  textfileDir = "/var/lib/prometheus-node-exporter-textfiles";
in {
  imports = [./monitoring-probes.nix];

  # Agenix secret for Grafana secret key
  age.secrets.grafana-secret-key = {
    file = ../../secrets/grafana-secret-key.age;
    mode = "0400";
    owner = "grafana";
    group = "grafana";
  };

  # Prometheus monitoring (host service)
  services.prometheus = lib.mkIf cfg.services.prometheus.enable {
    enable = true;
    inherit (cfg.services.prometheus) port;

    # Alertmanager integration
    alertmanagers = [
      {
        static_configs = [{targets = ["localhost:9093"];}];
      }
    ];

    # Scrape configurations
    scrapeConfigs = let
      mkServiceScrapeConfig = name: service: {
        job_name = name;
        static_configs = [
          {
            targets = [
              (
                if service.host == "maitred" && service.containerIP == null
                then "localhost:${toString service.port}"
                else if service.host == "maitred" && service.containerIP != null && name == "reverse-proxy"
                then "${cfg.networks.reverseProxyIP}:2019"
                else if service.host == "rich-evans"
                then "10.100.0.40:${toString service.port}"
                else "localhost:${toString service.port}"
              )
            ];
          }
        ];
      };

      serviceScrapeConfigs = lib.mapAttrsToList mkServiceScrapeConfig (
        lib.filterAttrs (
          name: service:
            service.enable
            && (name == "prometheus" || name == "reverse-proxy")
        )
        cfg.services
      );

      # All nebula hosts running node_exporter
      nodeExporterConfig = {
        job_name = "node-exporter";
        static_configs = [
          {
            targets = [
              "localhost:9100" # maitred
              "10.100.0.40:9100" # rich-evans
              "10.100.0.10:9100" # historian
              "10.100.0.6:9100" # total-eclipse
            ];
          }
        ];
      };

      # Blog reachability from inside the network
      blackboxBlogInternal = {
        job_name = "blackbox-blog-internal";
        metrics_path = "/probe";
        params = {module = ["http_2xx"];};
        static_configs = [{targets = ["https://blog.kimb.dev"];}];
        relabel_configs = [
          {source_labels = ["__address__"]; target_label = "__param_target";}
          {source_labels = ["__param_target"]; target_label = "instance";}
          {target_label = "__address__"; replacement = "localhost:9115";}
        ];
      };

      # Blog reachability from outside (via oracle blackbox)
      blackboxBlogExternal = {
        job_name = "blackbox-blog-external";
        metrics_path = "/probe";
        params = {module = ["http_2xx"];};
        static_configs = [{targets = ["https://blog.kimb.dev"];}];
        relabel_configs = [
          {source_labels = ["__address__"]; target_label = "__param_target";}
          {source_labels = ["__param_target"]; target_label = "instance";}
          {target_label = "__address__"; replacement = "10.100.0.2:9115";}
        ];
      };
    in
      [nodeExporterConfig blackboxBlogInternal blackboxBlogExternal] ++ serviceScrapeConfigs;

    # Alert rules
    ruleFiles = [
      (pkgs.writeText "sre-alerts.yml" (
        lib.generators.toYAML {} {
          groups = [
            {
              name = "sre-blog";
              rules = [
                {
                  alert = "BlogUnreachable";
                  expr = ''probe_success{job="blackbox-blog-external"} == 0'';
                  for = "2m";
                  labels.severity = "critical";
                  annotations.summary = "blog.kimb.dev unreachable from oracle (external probe)";
                }
              ];
            }
            {
              name = "sre-ollama";
              rules = [
                {
                  alert = "OllamaUnreachable";
                  expr = ''ollama_up == 0'';
                  for = "5m";
                  labels.severity = "warning";
                  annotations.summary = "Ollama on {{ $labels.host }} unreachable for 5m";
                }
              ];
            }
            {
              name = "sre-lifecoach";
              rules = [
                {
                  alert = "LifecoachStale";
                  expr = ''lifecoach_last_run_staleness_seconds > 14400'';
                  for = "0m";
                  labels.severity = "warning";
                  annotations.summary = "Lifecoach-organism has not run for {{ $value }}s (>4h)";
                }
              ];
            }
            {
              name = "sre-node";
              rules = [
                {
                  alert = "NodeExporterDown";
                  expr = ''up{job="node-exporter"} == 0'';
                  for = "5m";
                  labels.severity = "critical";
                  annotations.summary = "Node exporter on {{ $labels.instance }} down for 5m";
                }
              ];
            }
            {
              name = "sre-systemd";
              rules = [
                {
                  alert = "UnitFailed";
                  expr = ''node_systemd_unit_state{state="failed"} == 1'';
                  for = "10m";
                  labels.severity = "warning";
                  annotations.summary = "systemd unit {{ $labels.name }} failed on {{ $labels.instance }} for >10m";
                }
              ];
            }
            {
              name = "sre-restic";
              rules = [
                {
                  alert = "ResticBackupStale";
                  expr = ''restic_backup_staleness_seconds > 86400'';
                  for = "0m";
                  labels.severity = "warning";
                  annotations.summary = "Restic backup on {{ $labels.instance }} has not completed in {{ $value }}s (>24h)";
                }
              ];
            }
          ];
        }
      ))
    ];

    # Retention policy
    extraFlags = [
      "--storage.tsdb.retention.time=90d"
      "--storage.tsdb.retention.size=10GB"
    ];

    # Node exporter (local, with textfile collector)
    exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = ["systemd" "processes"];
      listenAddress = "0.0.0.0";
      openFirewall = false;
      extraFlags = ["--collector.textfile.directory=${textfileDir}"];
    };

    # Blackbox exporter for HTTP probes
    exporters.blackbox = {
      enable = true;
      port = 9115;
      openFirewall = false;
      configFile = pkgs.writeText "blackbox.yml" (
        lib.generators.toYAML {} {
          modules = {
            http_2xx = {
              prober = "http";
              timeout = "5s";
              http = {
                valid_status_codes = [200];
                method = "GET";
              };
            };
          };
        }
      );
    };

    # Alertmanager — fires webhooks to SRE agent on rich-evans
    alertmanager = {
      enable = true;
      port = 9093;
      openFirewall = false;
      configuration = {
        global.resolve_timeout = "5m";
        route = {
          receiver = "sre-webhook";
          group_by = ["alertname" "instance"];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
          routes = [
            {
              match = {severity = "critical";};
              receiver = "sre-webhook";
              repeat_interval = "4h";
            }
          ];
        };
        inhibit_rules = [
          {
            source_match = {alertname = "NodeExporterDown";};
            target_match = {alertname = "OllamaUnreachable";};
            equal = [];
          }
        ];
        receivers = [
          {
            name = "sre-webhook";
            webhook_configs = [
              {
                url = "http://10.100.0.40:9095/webhook";
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };
  };

  # Journal remote sink — receives logs from all nebula hosts
  users.users.systemd-journal-remote = {
    isSystemUser = true;
    group = "systemd-journal-remote";
  };
  users.groups.systemd-journal-remote = {};

  systemd.tmpfiles.rules = [
    "d /var/log/journal/remote 0755 systemd-journal-remote systemd-journal-remote -"
  ];

  systemd.sockets.systemd-journal-remote = {
    description = "Journal Remote Sink";
    listenStreams = ["19532"];
    wantedBy = ["sockets.target"];
  };

  systemd.services.systemd-journal-remote = {
    description = "Journal Remote Sink";
    requires = ["systemd-journal-remote.socket"];
    after = ["systemd-journal-remote.socket"];
    serviceConfig = {
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-journal-remote --output=/var/log/journal/remote/";
      User = "systemd-journal-remote";
      Group = "systemd-journal-remote";
    };
  };

  # Grafana visualization (host service)
  services.grafana = lib.mkIf cfg.services.grafana.enable {
    enable = true;

    settings = {
      server = {
        http_port = cfg.services.grafana.port;
        http_addr = "0.0.0.0";
        domain = "${cfg.services.grafana.subdomain}.${cfg.domain}";
        root_url = "https://${cfg.services.grafana.subdomain}.${cfg.domain}";
      };

      security = {
        admin_user = cfg.admin.name;
        admin_password = "admin"; # TODO: Change default password
        secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
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
      "br-lan".allowedTCPPorts = lib.flatten [
        (lib.optional cfg.services.grafana.enable cfg.services.grafana.port)
        (lib.optional cfg.services.prometheus.enable cfg.services.prometheus.port)
        [9093 9100 19532] # alertmanager + node exporter + journal-remote
      ];
      "nebula1".allowedTCPPorts = lib.flatten [
        (lib.optional cfg.services.grafana.enable cfg.services.grafana.port)
        (lib.optional cfg.services.prometheus.enable cfg.services.prometheus.port)
        [9093 9100 19532] # alertmanager + node exporter + journal-remote
      ];
    };
  };
}
