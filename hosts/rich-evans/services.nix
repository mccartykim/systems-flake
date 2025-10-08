# Rich-Evans services configuration using kimb-services options system
{ config, lib, pkgs, ... }:

let
  cfg = config.kimb;

in {
  # Copyparty file sharing service (host service)
  services.copyparty = lib.mkIf cfg.services.copyparty.enable {
    enable = true;
    
    settings = {
      # Listen on all interfaces for LAN and Nebula access
      i = "0.0.0.0";
      # Keep default port 3923

      # Header-based SSO authentication with Authelia
      # Map Remote-User header from Authelia to Copyparty users
      idp-h-usr = "Remote-User";
      idp-h-grp = "Remote-Groups";

      # Trust maitred proxy for X-Forwarded-For and SSO headers
      xff-src = "10.100.0.0/16,192.168.100.0/24";

      # CORS configuration for reverse proxy uploads
      acao = "https://files.${cfg.domain}"; # Allow cross-origin from reverse proxy domain
      acam = "GET,POST,PUT,DELETE,HEAD,OPTIONS"; # Allow necessary HTTP methods
    };

    # Configure volumes with SSO user permissions
    volumes = {
      "/" = {
        path = "/mnt/seagate/copyparty";
        access = {
          # Give kimb full admin permissions via SSO header
          rwadmG = [cfg.admin.name];
          # Allow all authenticated users to read
          r = "*";
        };
      };
    };
  };

  # Home Assistant smart home platform (OCI container)
  virtualisation.oci-containers.containers.homeassistant = lib.mkIf cfg.services.homeassistant.enable {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    autoStart = true;

    # No port mapping needed with host networking
    # ports = [ "${toString cfg.services.homeassistant.port}:8123" ];

    volumes = [
      "/var/lib/hass:/config"
      "/etc/localtime:/etc/localtime:ro"
    ];

    environment = {
      TZ = "America/New_York";
    };

    extraOptions = [
      "--privileged"
      "--network=host"
    ];
  };

  # Homepage dashboard (host service) - local only
  services.homepage-dashboard = lib.mkIf cfg.services.homepage.enable {
    enable = true;
    openFirewall = false; # LAN access only
    listenPort = cfg.services.homepage.port;
    
    settings = {
      title = "Rich-Evans Services";
      
      services = [
        {
          "File Storage" = lib.mkIf cfg.services.copyparty.enable [
            {
              "Copyparty" = {
                href = "http://localhost:${toString cfg.services.copyparty.port}";
                description = "Local file sharing and upload";
                server = "localhost";
                container = false;
              };
            }
          ];
        }
        {
          "Smart Home" = lib.mkIf cfg.services.homeassistant.enable [
            {
              "Home Assistant" = {
                href = "http://localhost:${toString cfg.services.homeassistant.port}";
                description = "Home automation platform";
                server = "localhost";
                container = true;
              };
            }
          ];
        }
        {
          "System Monitoring" = [
            {
              "Maitred Grafana" = {
                href = "https://grafana.${cfg.domain}";
                description = "System metrics dashboard";
                server = "10.100.0.50"; # maitred Nebula IP
                container = false;
              };
            }
            {
              "Maitred Homepage" = {
                href = "https://home.${cfg.domain}";
                description = "Main services dashboard";
                server = "10.100.0.50"; # maitred Nebula IP  
                container = false;
              };
            }
          ];
        }
      ];
    };
  };

  # Firewall configuration for enabled services
  networking.firewall = {
    allowedTCPPorts = lib.flatten [
      # Copyparty main port
      (lib.optional cfg.services.copyparty.enable cfg.services.copyparty.port)
      
      # Copyparty additional ports  
      (lib.optionals cfg.services.copyparty.enable [ 3921 3945 3969 3990 ])
      
      # Home Assistant
      (lib.optional cfg.services.homeassistant.enable cfg.services.homeassistant.port)
      
      # Homepage (LAN only)
      (lib.optional cfg.services.homepage.enable cfg.services.homepage.port)
      
      # CUPS printing
      [ 631 ]
    ];
    
    allowedUDPPorts = lib.optionals cfg.services.copyparty.enable [
      3969  # TFTP
    ];
    
    allowedTCPPortRanges = lib.optionals cfg.services.copyparty.enable [
      { from = 12000; to = 12099; }  # Dynamic ports for copyparty
    ];
  };

  # Enable OCI containers backend for Home Assistant
  virtualisation.oci-containers.backend = lib.mkIf cfg.services.homeassistant.enable "podman";
  virtualisation.podman.enable = lib.mkIf cfg.services.homeassistant.enable true;
  
  # Create necessary directories
  systemd.tmpfiles.rules = lib.flatten [
    (lib.optional cfg.services.homeassistant.enable "d /var/lib/hass 0755 root root -")
    (lib.optional cfg.services.copyparty.enable "d /mnt/storage 0755 root root -")
    (lib.optional cfg.services.copyparty.enable "d /mnt/storage/public 0755 root root -")
  ];
}
