# Homepage dashboard configuration for maitred
# Modern application dashboard with service integrations
{
  config,
  pkgs,
  ...
}: {
  # Homepage dashboard service
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    openFirewall = false; # Only accessible via Caddy proxy

    # Allow access from home.kimb.dev and local IPs
    allowedHosts = "home.kimb.dev,192.168.100.1:8082,localhost:8082";

    settings = {
      title = "maitred router";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
      hideVersion = true;
    };

    # Services configuration (using proper syntax)
    services = [
      {
        Network = [
          {
            Monitoring = {
              href = "https://grafana.kimb.dev";
              description = "Grafana Dashboards";
              icon = "grafana";
            };
          }
          {
            Metrics = {
              href = "https://prometheus.kimb.dev";
              description = "Prometheus Metrics";
              icon = "prometheus";
            };
          }
        ];
      }
      {
        "Public Services" = [
          {
            Blog = {
              href = "https://kimb.dev";
              description = "Personal Blog";
              icon = "memos";
            };
          }
        ];
      }
    ];

    # Bookmarks
    bookmarks = [
      {
        "Network Tools" = [
          {"What's My IP" = [{href = "https://whatismyipaddress.com/";}];}
          {"DNS Checker" = [{href = "https://dnschecker.org/";}];}
          {"Speed Test" = [{href = "https://fast.com/";}];}
        ];
      }
      {
        Documentation = [
          {
            "NixOS Manual" = [
              {
                href = "https://nixos.org/manual/nixos/stable/";
                icon = "si-nixos";
              }
            ];
          }
          {"Grafana Docs" = [{href = "https://grafana.com/docs/";}];}
          {"Prometheus Docs" = [{href = "https://prometheus.io/docs/";}];}
        ];
      }
    ];

    # Widgets for homepage
    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        search = {
          provider = "duckduckgo";
          target = "_blank";
        };
      }
    ];
  };
}
