# Centralized service configuration for kimb.dev infrastructure
# Auto-injected via commonModules — each host picks up its services
# based on config.networking.hostName, so no per-host wiring is needed.
{config, ...}: let
  hostServices = {
    # Rich Evans services
    rich-evans = {
      copyparty = {
        enable = true;
        port = 3923;
        subdomain = "files";
        host = "rich-evans";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
      homepage = {
        enable = true;
        port = 8082;
        subdomain = "home-rich";
        host = "rich-evans";
        auth = "none";
        publicAccess = false;
        websockets = false;
      };
      homeassistant = {
        enable = true;
        port = 8123;
        subdomain = "hass";
        host = "rich-evans";
        auth = "builtin";
        publicAccess = true;
        websockets = true;
      };
      life-coach-dashboard = {
        enable = true;
        # lifecoach-organism dashboard runs on 8586; the old
        # org-life-coach dashboard on 8585 is now mkForce-disabled.
        port = 8586;
        subdomain = "coach";
        host = "rich-evans";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
    };

    # Maitred services (router + reverse proxy)
    maitred = {
      authelia = {
        enable = true;
        port = 9091;
        subdomain = "auth";
        host = "maitred";
        auth = "none";
        publicAccess = true;
        websockets = false;
      };
      grafana = {
        enable = true;
        port = 3000;
        subdomain = "grafana";
        host = "maitred";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
      prometheus = {
        enable = true;
        port = 9090;
        subdomain = "prometheus";
        host = "maitred";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
      homepage = {
        enable = true;
        port = 8082;
        subdomain = "home";
        host = "maitred";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
      blog = {
        enable = true;
        port = 8080;
        subdomain = "blog";
        host = "maitred";
        containerIP = "192.168.100.3";
        auth = "none";
        publicAccess = true;
        websockets = false;
      };
      reverse-proxy = {
        enable = true;
        port = 80;
        subdomain = "www";
        host = "maitred";
        containerIP = "192.168.100.2";
        auth = "none";
        publicAccess = true;
        websockets = false;
      };
      # These services run on rich-evans but are proxied through maitred
      homeassistant = {
        enable = true;
        port = 8123;
        subdomain = "hass";
        host = "rich-evans";
        auth = "builtin";
        publicAccess = true;
        websockets = true;
      };
      matrix = {
        enable = true;
        port = 6167;
        subdomain = "matrix";
        host = "rich-evans";
        auth = "builtin";
        publicAccess = true;
        websockets = true;
      };
      jellyfin = {
        enable = true;
        port = 8096;
        subdomain = "media";
        host = "historian";
        auth = "builtin";
        publicAccess = true;
        websockets = true;
      };
      buildbot = {
        enable = true;
        port = 80;
        subdomain = "buildbot";
        host = "rich-evans";
        auth = "none";
        publicAccess = true;
        websockets = true;
      };
      life-coach-dashboard = {
        enable = true;
        # lifecoach-organism dashboard runs on 8586; the old
        # org-life-coach dashboard on 8585 is now mkForce-disabled.
        port = 8586;
        subdomain = "coach";
        host = "rich-evans";
        auth = "authelia";
        publicAccess = true;
        websockets = false;
      };
    };
  };
in {
  kimb.services = hostServices.${config.networking.hostName} or {};
}
