# Homepage dashboard — the consolidated instance, ported from the rich-evans
# framework (hosts/rich-evans/services.nix) at a3j.5. rich-evans's instance
# retires with the registry move (its `services.homepage-dashboard` block is
# mkIf'd on cfg.services.homepage.enable, which turns off when the entry
# leaves its bucket); maitred keeps its own (subdomain "home") until phase 5.
#
# Fully declarative — no state to migrate (settings render to
# /var/lib/homepage-dashboard config at build time). LAN-only, same posture
# as on rich-evans: openFirewall = false here + one allowedTCPPort below for
# LAN browser access on :8082 (no kimb.dev vhost — publicAccess=false in the
# registry entry, so maitred generates neither a vhost nor a socat forwarder
# for it). Bookmark flips to historian's LAN IP after the cutover.
{
  config,
  lib,
  ...
}: let
  cfg = config.kimb;
in {
  services.homepage-dashboard = lib.mkIf cfg.services.homepage.enable {
    enable = true;
    openFirewall = false; # we open the port ourselves below (LAN access only)
    listenPort = cfg.services.homepage.port;
    # gethomepage validates the Host header by default and rejects the LAN
    # IP ("Host validation failed") — allow the addresses the dashboard is
    # actually reached on: local + historian's LAN IP (browser bookmark) +
    # the nebula IP (personal devices over the mesh).
    allowedHosts = "localhost,127.0.0.1,192.168.69.167:8082,10.100.0.10:8082";

    settings = {
      # The consolidated dashboard: what lives HERE now. The a3j.6 cohort
      # (copyparty, HA) and the a3j.8.1 monitoring stack (grafana,
      # prometheus) are all local — remaining "elsewhere" fleet services are
      # on maitred (retiring at a3j.8.2+) and rich-evans (a3j.7).
      title = "Historian Services";

      services = [
        {
          "Reading" = [
            {
              "Borges" = {
                href = "http://localhost:${toString cfg.services.borges.port}";
                description = "EPUB server (OPDS + reader)";
                server = "localhost";
                container = false;
              };
            }
          ];
        }
        {
          "Knitwork" = [
            {
              "Knit AppView" = {
                href = "http://localhost:${toString cfg.services.knit.port}";
                description = "Lexicon host + firehose indexer";
                server = "localhost";
                container = false;
              };
            }
            {
              "Knit Web" = {
                href = "http://localhost:${toString cfg.services.knit-web.port}";
                description = "KMP SPA (nspawn container)";
                server = "localhost";
                container = true;
              };
            }
          ];
        }
        {
          "Media" = [
            {
              "Jellyfin" = {
                href = "http://localhost:8096";
                description = "Media server";
                server = "localhost";
                container = false;
              };
            }
            {
              "MPD Stream" = {
                href = "http://localhost:8666";
                description = "Choirmaster music stream (httpd)";
                server = "localhost";
                container = false;
              };
            }
          ];
        }
        {
          "Smart Home" = [
            {
              "Home Assistant" = {
                href = "https://hass.${cfg.domain}";
                description = "Smart home (moved here at a3j.6)";
                server = "localhost";
                container = false;
              };
            }
          ];
        }
        {
          "Files" = [
            {
              "Copyparty" = {
                # No files.kimb.dev vhost exists (no maitred duplicate —
                # deliberate); direct access is http://192.168.69.167:3923.
                href = "http://localhost:3923";
                description = "File sharing (moved here at a3j.6)";
                server = "localhost";
                container = false;
              };
            }
          ];
        }
        {
          "Monitoring" = [
            {
              "Grafana" = {
                href = "https://grafana.${cfg.domain}";
                description = "Metrics dashboards (moved here at a3j.8.1)";
                server = "localhost";
                container = false;
              };
            }
            {
              "Prometheus" = {
                href = "https://prometheus.${cfg.domain}";
                description = "Metrics collection (moved here at a3j.8.1)";
                server = "localhost";
                container = false;
              };
            }
          ];
        }
      ];
    };
  };

  # LAN browser access on the homepage port (same posture as rich-evans's
  # framework: the port is open only while the service is enabled).
  networking.firewall.allowedTCPPorts =
    lib.optional cfg.services.homepage.enable cfg.services.homepage.port;
}
