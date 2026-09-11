# Monitoring stack with SRE observability (Phase 0)
# Prometheus + Grafana + Alertmanager + blackbox + journal-remote
#
# === a3j.8.1 (2026-09-11): the stack moved to historian — see
# hosts/historian/monitoring.nix. What remains here:
#   - the node_exporter (UNgated): historian's prometheus scrapes maitred
#     at 10.100.0.50:9100, with the textfile collector dir wired up.
#   - the full prometheus/grafana/blackbox blocks, now gated on the
#     registry `host` so they turn off when the service entry moves away
#     (maitred's bucket keeps enable=true duplicates to drive the socat
#     forwarders + vhosts + authelia + DNS). ROLLBACK = flip
#     services/default.nix `host` back to "maitred" and re-apply; the
#     grafana user + secret + state are recreated from config on this
#     host (the old /var/lib state was rsynced away — restoring it is a
#     manual affair from the historian copy).
#   - the firewall block unchanged: 3000/9090/9100 stay open on
#     br-lan/nebula1 so the socat forwarders (grafana-proxy/prometheus-
#     proxy) serve the same LAN paths the old local stack did.
# ===
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
  # Registry-driven local-service gates: the units only run when the
  # registry says the service lives on maitred.
  prometheusLocal =
    cfg.services.prometheus.enable && cfg.services.prometheus.host == "maitred";
  grafanaLocal =
    cfg.services.grafana.enable && cfg.services.grafana.host == "maitred";
  textfileDir = "/var/lib/prometheus-node-exporter-textfiles";
in {
  # Probes disabled along with SRE observability stack
  # imports = [./monitoring-probes.nix];

  # Agenix secret for Grafana secret key — only decrypted while grafana
  # actually runs here (the grafana user does not exist when the service
  # is off, and agenix chown would fail the activation).
  age.secrets.grafana-secret-key = lib.mkIf grafanaLocal {
    file = ../../secrets/grafana-secret-key.age;
    mode = "0400";
    owner = "grafana";
    group = "grafana";
  };

  # Textfile collector dir for the always-on node exporter.
  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 nobody nogroup -"
  ];

  # Prometheus monitoring — one attrset (NixOS forbids two services.prometheus
  # definitions per module), so the pieces gate individually:
  #   - exporters.node is UNGATED (maitred stays a scrape target at
  #     10.100.0.50:9100 for historian's prometheus).
  #   - the server + blackbox exporter gate on the registry `host` — they
  #     turn off when the entry moves away (a3j.8.1), since the nixpkgs
  #     module wraps everything in mkIf enable the disabled values are inert.
  services.prometheus = {
    exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = ["systemd" "processes"];
      listenAddress = "0.0.0.0";
      openFirewall = false;
      extraFlags = ["--collector.textfile.directory=${textfileDir}"];
    };

    enable = lib.mkIf prometheusLocal true;
    port = lib.mkIf prometheusLocal cfg.services.prometheus.port;

    # Scrape configurations
    scrapeConfigs = lib.mkIf prometheusLocal (let
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

      # Blog reachability from inside the network — probes the blog container
      # directly via HTTP to avoid DNS hairpin (unbound resolves blog.kimb.dev to
      # maitred's own LAN IP, but DNAT only applies to LAN-originated traffic,
      # not locally-originated traffic from the blackbox_exporter).
      # TLS reachability is covered by blackbox-blog-external (probes from oracle).
      blackboxBlogInternal = let
        blog = cfg.services.blog;
      in {
        job_name = "blackbox-blog-internal";
        metrics_path = "/probe";
        params = {module = ["http_2xx"];};
        static_configs = [
          {
            targets = ["http://${blog.containerIP}:${toString blog.port}/"];
            labels = {probe = "internal";};
          }
        ];
        relabel_configs = [
          {
            source_labels = ["__address__"];
            target_label = "__param_target";
          }
          {
            target_label = "instance";
            replacement = "blog.kimb.dev";
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
        static_configs = [{targets = ["https://blog.kimb.dev"];}];
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
    in
      [nodeExporterConfig blackboxBlogInternal blackboxBlogExternal] ++ serviceScrapeConfigs);

    # Retention policy
    extraFlags = lib.mkIf prometheusLocal [
      "--storage.tsdb.retention.time=90d"
      "--storage.tsdb.retention.size=10GB"
    ];

    # Blackbox exporter for HTTP probes (the a3j.8.1 historian stack runs
    # its own; nothing probes maitred's once the server is gated off)
    exporters.blackbox = lib.mkIf prometheusLocal {
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

  # Grafana visualization (host service) — a3j.8.1-gated on registry host
  services.grafana = lib.mkIf grafanaLocal {
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

    provision = lib.mkIf prometheusLocal {
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

  # Firewall rules for monitoring services. The lib.optional gates stay on
  # plain `enable` (not the Local gates): after a3j.8.1 the ports serve the
  # socat forwarders (grafana-proxy/prometheus-proxy -> historian), so LAN
  # paths like http://192.168.69.1:3000 keep working through the move.
  networking.firewall = {
    interfaces = {
      "br-lan".allowedTCPPorts = lib.flatten [
        (lib.optional cfg.services.grafana.enable cfg.services.grafana.port)
        (lib.optional cfg.services.prometheus.enable cfg.services.prometheus.port)
        [9100] # node exporter
      ];
      "nebula1".allowedTCPPorts = lib.flatten [
        (lib.optional cfg.services.grafana.enable cfg.services.grafana.port)
        (lib.optional cfg.services.prometheus.enable cfg.services.prometheus.port)
        [9100] # node exporter
      ];
    };
  };
}
