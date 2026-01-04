# Rich-Evans services configuration using kimb-services options system
{
  config,
  lib,
  pkgs,
  ...
}: let
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

  # Home Assistant smart home platform (native NixOS service)
  services.home-assistant = lib.mkIf cfg.services.homeassistant.enable {
    enable = true;
    openFirewall = true;

    extraComponents = [
      "default_config"
      "met"
      "radio_browser"
      "esphome" # ESP32 integration
      "zeroconf" # Device discovery
      "ssdp"
      "api" # REST API for Claude skills
      "mobile_app"
      "androidtv_remote" # Android TV control
      "cast" # Chromecast/Google Cast
      "thread" # Thread mesh networking
      "otbr" # OpenThread Border Router
      "vacuum" # Vacuum base
      "mqtt" # MQTT for Valetudo
    ];

    config = {
      default_config = {};
      http = {
        server_host = "0.0.0.0";
        server_port = cfg.services.homeassistant.port;
        use_x_forwarded_for = true;
        trusted_proxies = [
          "10.100.0.50" # maitred Nebula
          "192.168.69.1" # maitred LAN
          "192.168.100.0/24" # Container network
          "127.0.0.1"
        ];
      };
      api = {};
      # Shell commands for life-coach agent button press interrupts
      # One per button since shell_command doesn't support templating
      shell_command = {
        signal_desk_button = "/etc/life-coach-agent/signal_button_press.sh desk_button";
        signal_desk_task_1 = "/etc/life-coach-agent/signal_button_press.sh desk_task_1";
        signal_desk_task_2 = "/etc/life-coach-agent/signal_button_press.sh desk_task_2";
        signal_desk_task_3 = "/etc/life-coach-agent/signal_button_press.sh desk_task_3";
        signal_bathroom = "/etc/life-coach-agent/signal_button_press.sh bathroom";
        signal_litterbox = "/etc/life-coach-agent/signal_button_press.sh litterbox";
        signal_shower_button = "/etc/life-coach-agent/signal_button_press.sh shower_button";
        signal_bass_guitar = "/etc/life-coach-agent/signal_button_press.sh bass_guitar";
        signal_garage_button = "/etc/life-coach-agent/signal_button_press.sh garage_button";
        signal_kitchen_front_door = "/etc/life-coach-agent/signal_button_press.sh kitchen_front_door";
        signal_user_input = "/etc/life-coach-agent/signal_user_input.sh";
      };
      # All automations are in /var/lib/hass/automations.yaml
      automation = "!include automations.yaml";
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";
      # Text input for life-coach agent user prompts
      input_text = {
        life_coach_input = {
          name = "Life Coach Input";
          max = 255;
          icon = "mdi:message-text";
        };
      };
    };
  };

  # Allow HA to write to life-coach-agent state directory for button interrupts
  # (HA uses ProtectSystem=strict by default, limiting writes to /var/lib/hass)
  systemd.services.home-assistant.serviceConfig.ReadWritePaths = [
    "/var/lib/life-coach-agent"
  ];

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
      (lib.optionals cfg.services.copyparty.enable [3921 3945 3969 3990])

      # Home Assistant
      (lib.optional cfg.services.homeassistant.enable cfg.services.homeassistant.port)

      # ESPHome native API (for ESP32 device discovery)
      (lib.optional cfg.services.homeassistant.enable 6053)

      # Homepage (LAN only)
      (lib.optional cfg.services.homepage.enable cfg.services.homepage.port)

      # CUPS printing
      [631]
    ];

    allowedUDPPorts = lib.optionals cfg.services.copyparty.enable [
      3969 # TFTP
    ];

    allowedTCPPortRanges = lib.optionals cfg.services.copyparty.enable [
      {
        from = 12000;
        to = 12099;
      } # Dynamic ports for copyparty
    ];
  };

  # Create necessary directories
  systemd.tmpfiles.rules = lib.flatten [
    # Home Assistant needs hass user ownership (created by native service)
    (lib.optional cfg.services.homeassistant.enable "d /var/lib/hass 0750 hass hass -")
    (lib.optional cfg.services.homeassistant.enable "f /var/lib/hass/automations.yaml 0644 hass hass -")
    (lib.optional cfg.services.homeassistant.enable "f /var/lib/hass/scripts.yaml 0644 hass hass -")
    (lib.optional cfg.services.homeassistant.enable "f /var/lib/hass/scenes.yaml 0644 hass hass -")
    # Copyparty storage
    (lib.optional cfg.services.copyparty.enable "d /mnt/storage 0755 root root -")
    (lib.optional cfg.services.copyparty.enable "d /mnt/storage/public 0755 root root -")
  ];
}
