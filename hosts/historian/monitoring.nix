# Monitoring stack — the a3j.8.1 migration from maitred (which kept a
# gated copy in hosts/maitred/monitoring.nix for rollback). Prometheus +
# Grafana + blackbox-exporter run HERE now; maitred keeps only its node
# exporter (scrape target 10.100.0.50:9100) plus the grafana/prometheus
# socat forwarders driven by the maitred-bucket registry duplicates.
#
# Port note: grafana keeps its conventional 3000 — forgejo moved to 3030
# in the same push (its only HTTP consumers are flake-managed:
# bridge-scribe's FORGE_URL + the nebula inbound rule).
#
# Scrape-config deltas vs the maitred original:
#   - node-exporter: same four fleet targets; localhost is now historian
#     (kimb.observability supplies this host's exporter), 10.100.0.50 is
#     maitred's retained exporter, rich-evans/total-eclipse stay listed
#     but down until their observability is re-enabled (deliberately off
#     — "too noisy, low value" — re-enabling is a user decision).
#   - blackbox-blog-internal: probes https://blog.kimb.dev through the
#     LOCAL blackbox. From historian (a LAN client) the split-brain DNS +
#     maitred PREROUTING DNAT path works, so this now exercises the full
#     LAN journey: historian -> maitred DNAT -> Caddy -> blog container.
#     (On maitred the same probe had to hit the container IP directly
#     because router-originated traffic skips the DNAT.)
#   - blackbox-blog-external: unchanged — oracle's blackbox (10.100.0.2)
#     probes from the WAN vantage.
#   - The reverse-proxy (Caddy :2019) scrape is DROPPED: it was already
#     down on maitred (metrics admin endpoint never enabled) and the
#     192.168.100.x container bridge is unreachable from here anyway.
#
# State: /var/lib/grafana (sqlite + dashboards) and /var/lib/prometheus2
# (TSDB, 90d history) moved via the two-pass rsync runbook; ownership
# fixed BY NAME post-move (numeric uid collision class rule). The TSDB
# is excluded from restic (regenerable, up to 10G of churn per pass) —
# grafana.db rides the normal /var/lib backup.
#
# Node exporter: provided by kimb.observability (enabled in
# configuration.nix), NOT here — the restic staleness probe and
# ollama-health textfiles land in its collector dir.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
in {
  # Agenix secret for Grafana secret key — pre-keyed for historian at
  # a3j.10 (secrets/secrets.nix grafana-secret-key.age), no rekey needed.
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

    # Scrape configurations
    scrapeConfigs = let
      # Prometheus self-scrape (localhost now that it runs here)
      selfScrape = {
        job_name = "prometheus";
        static_configs = [
          {targets = ["localhost:${toString cfg.services.prometheus.port}"];}
        ];
      };

      # All nebula hosts running node_exporter. historian (localhost) and
      # maitred are up; rich-evans + total-eclipse are listed but down
      # until their kimb.observability is re-enabled.
      nodeExporterConfig = {
        job_name = "node-exporter";
        static_configs = [
          {
            targets = [
              "localhost:9100" # historian
              "10.100.0.50:9100" # maitred
              "10.100.0.40:9100" # rich-evans
              "10.100.0.6:9100" # total-eclipse
            ];
          }
        ];
      };

      # Blog reachability over the LAN path (historian -> maitred DNAT ->
      # Caddy -> blog container) via the local blackbox exporter.
      blackboxBlogInternal = {
        job_name = "blackbox-blog-internal";
        metrics_path = "/probe";
        params = {module = ["http_2xx"];};
        static_configs = [
          {
            targets = ["https://blog.${cfg.domain}"];
            labels = {probe = "internal";};
          }
        ];
        relabel_configs = [
          {
            source_labels = ["__address__"];
            target_label = "__param_target";
          }
          {
            source_labels = ["__param_target"];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "localhost:9115";
          }
        ];
      };

      # Blog reachability from outside (via oracle blackbox)
      blackboxBlogExternal = {
        job_name = "blackbox-blog-external";
        metrics_path = "/probe";
        params = {module = ["http_2xx"];};
        static_configs = [{targets = ["https://blog.${cfg.domain}"];}];
        relabel_configs = [
          {
            source_labels = ["__address__"];
            target_label = "__param_target";
          }
          {
            source_labels = ["__param_target"];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "10.100.0.2:9115";
          }
        ];
      };
    in [selfScrape nodeExporterConfig blackboxBlogInternal blackboxBlogExternal];

    # Retention policy
    extraFlags = [
      "--storage.tsdb.retention.time=90d"
      "--storage.tsdb.retention.size=10GB"
    ];

    # NOTE: the node exporter is NOT defined here — kimb.observability
    # (enabled in configuration.nix) provides it on :9100 with the
    # textfile collector dir. Defining it in both places concatenated the
    # list options (duplicate --collector.* / --collector.textfile.directory
    # flags) and the unit crash-looped at first activation (a3j.8.1).

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

  # Firewall: LAN parity with maitred's old posture (grafana bookmark by
  # LAN IP, prometheus webui, node metrics). Nebula1 is already trusted.
  networking.firewall.allowedTCPPorts = lib.flatten [
    (lib.optional cfg.services.grafana.enable cfg.services.grafana.port)
    (lib.optional cfg.services.prometheus.enable cfg.services.prometheus.port)
    [9100] # node exporter
  ];

  # Nebula: maitred is a router (not a personal device), so its socat
  # forwarders (grafana-proxy :3000, prometheus-proxy :9090 -> this
  # host) need explicit inbound rules — same pattern as knit/borges/BFF.
  kimb.nebula.extraInboundRules = lib.optionals (cfg.services.grafana.enable && cfg.services.prometheus.enable) [
    {
      port = cfg.services.grafana.port;
      proto = "tcp";
      host = "maitred";
    }
    {
      port = cfg.services.prometheus.port;
      proto = "tcp";
      host = "maitred";
    }
  ];
}
