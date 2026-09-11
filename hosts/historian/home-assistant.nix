# Home Assistant + mosquitto — the a3j.6 phase-6a migration from rich-evans
# (ported from the framework blocks in hosts/rich-evans/services.nix).
# HA + mosquitto move TOGETHER: HA's mqtt integration talks to the broker at
# 127.0.0.1:1883 (UI-configured, rides the /var/lib/hass rsync unchanged), so
# the loopback relationship survives the move and only the VACUUM's own
# valetudo MQTT setting needs a manual repoint afterward (it dials the
# broker's LAN address — valetudo web UI at the robot, or its API).
#
# No USB hardware on rich-evans bound HA (checked /dev/serial + ttyACM*: none
# — the webcams are v4l2 and stay there; thread/otbr components are enabled
# with no Thread radio dongle in the fleet, so they port free). The Pixel
# iBeacon transmitter is the one range question: historian's hci0 scan came
# up empty in a short window — the ibeacon integration may degrade from the
# living room placement. Everything else (tplink, cast, vacuum, ESPHome
# native API — HA dials OUT to the ESPs) is LAN/network-bound.
#
# Consumers during the interim (organisms stay on rich-evans until a3j.7):
# their haUrl/HA_URL flips to http://10.100.0.10:8123 in the rich-evans host
# files (one line each); the ha-life-coach-token .age is already fleet-core
# keyed, and the daemons keep their local decryption — no secret change.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.kimb;
in {
  services.home-assistant = lib.mkIf cfg.services.homeassistant.enable {
    enable = true;

    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      valetudo-map-card
    ];

    extraComponents = [
      "default_config"
      "met"
      "radio_browser"
      "esphome" # ESP32 integration
      "zeroconf" # ESP/device discovery
      "ssdp"
      "api" # REST API for Claude skills
      "mobile_app"
      "androidtv_remote" # Android TV control
      "cast" # Chromecast/Google Cast
      "thread" # Thread mesh networking (no radio dongle — ports free)
      "otbr" # OpenThread Border Router (same)
      "tplink" # TP-Link Kasa switches + Tapo cameras
      "vacuum" # Vacuum base
      "mqtt" # MQTT for Valetudo
      "ibeacon" # BLE iBeacon → distance/RSSI sensor for the Pixel transmitter
    ];

    config = {
      homeassistant = {
        external_url = "https://hass.${cfg.domain}";
        internal_url = "http://10.100.0.10:${toString cfg.services.homeassistant.port}";
      };
      default_config = {};
      http = {
        server_host = ["0.0.0.0"];
        server_port = cfg.services.homeassistant.port;
        use_x_forwarded_for = true;
        trusted_proxies = [
          "10.100.0.50" # maitred Nebula (socat forwarder for hass.kimb.dev)
          "192.168.69.1" # maitred LAN
          "192.168.100.0/24" # Container network
          "127.0.0.1"
        ];
      };
      api = {};
      # UI-defined automations (existing) — these files ride the state rsync
      "automation ui" = "!include automations.yaml";
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";
      # Submit buttons for the vacuum organism (find-me / belay). The old
      # life-coach shell_command blocks were removed pre-migration; the
      # button-monitor sidecar polls HA REST directly.
      input_button = {
        vacuum_find_me = {
          name = "Vacuum: Come Find Me";
          icon = "mdi:map-marker-account";
        };
        vacuum_belay = {
          name = "Vacuum: Belay (I'm coming)";
          icon = "mdi:hand-back-right-off";
        };
      };
      # Hard kill switch for vacuum_organism. When on, the agent
      # refuses all motion and marks in-flight dispatches SKIPPED
      # with reason "off-duty". See vacuum_organism/HA_SETUP.md.
      input_boolean = {
        vacuum_offduty = {
          name = "Vacuum Organism Off-Duty";
          icon = "mdi:robot-off";
        };
      };
    };
  };

  # MQTT broker for Valetudo vacuum integration (LAN-only, no auth) — same
  # posture as on rich-evans; the vacuum dials this from the LAN after its
  # valetudo broker setting is repointed to 192.168.69.167:1883.
  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "0.0.0.0";
        port = 1883;
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
        acl = ["topic readwrite #"];
      }
    ];
  };

  # LAN exposure parity with the rich-evans framework block: HA frontend,
  # mosquitto (the vacuum), + mDNS for ESP discovery. 6053 (ESPHome native
  # API) is deliberately NOT opened: the ESPs are the SERVERS — HA dials out
  # to them — so no inbound hole is needed for existing UI-configured
  # integrations (their addresses ride the state rsync).
  networking.firewall = {
    allowedTCPPorts =
      lib.optional cfg.services.homeassistant.enable cfg.services.homeassistant.port
      ++ [1883];
    allowedUDPPorts = [5353]; # mDNS/Bonjour — ESP discovery from this host
  };

  # hass-owned state dirs (tmpfiles are no-ops once the rsync'd tree exists;
  # the mode fields only apply at creation). After the cutover push, the
  # rsync'd /var/lib/hass needs a one-time chown -R hass:hass (rich-evans's
  # numeric ids differ from this host's fresh hass user).
  systemd.tmpfiles.rules = lib.optionals cfg.services.homeassistant.enable [
    "d /var/lib/hass 0750 hass hass -"
    "f /var/lib/hass/automations.yaml 0644 hass hass -"
    "f /var/lib/hass/scripts.yaml 0644 hass hass -"
    "f /var/lib/hass/scenes.yaml 0644 hass hass -"
  ];

  # Nebula: HA frontend from any mesh node (maitred's socat for hass.kimb.dev
  # + the rich-evans organisms' interim haUrl at 10.100.0.10:8123 + personal
  # devices). Parity with rich-evans's old host=any rule.
  kimb.nebula.extraInboundRules = lib.optionals cfg.services.homeassistant.enable [
    {
      port = cfg.services.homeassistant.port;
      proto = "tcp";
      host = "any";
    }
  ];
}
