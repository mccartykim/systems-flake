# Consolidated Nebula mesh configuration
# Supports two cert modes:
#   1. Static (default): agenix-encrypted certs from `nix run .#generate-nebula-certs`
#   2. Dynamic: short-lived certs fetched from a signing service (24h refresh, 48h expiry)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.nebula;
  hostname = config.networking.hostName;
  registry = import ../hosts/nebula-registry.nix;

  # This host's config from registry
  hostConfig = registry.nodes.${hostname} or {};
  isLighthouse = hostConfig.isLighthouse or false;
  isRelay = hostConfig.isRelay or false;
  myIp = hostConfig.ip or "";

  # Helper: get IPs from node list, excluding our own
  getOtherIps = nodes: filter (ip: ip != myIp) (map (n: n.ip) nodes);

  # Lighthouses and relays from registry
  allLighthouses =
    filter (n: (n.isLighthouse or false) && n ? external)
    (attrValues registry.nodes);
  allRelays = filter (n: n.isRelay or false) (attrValues registry.nodes);

  # Derived config: exclude self from lighthouse/relay lists
  lighthouseIps =
    if isLighthouse
    then []
    else map (n: n.ip) allLighthouses;
  staticHosts = listToAttrs (map (n: nameValuePair n.ip [n.external]) allLighthouses);
  relayIps = getOtherIps allRelays;

  # Cert paths depend on mode
  certDir =
    if cfg.dynamicCerts.enable
    then "/var/lib/nebula-dynamic"
    else "/etc/nebula";
  caPath =
    if cfg.dynamicCerts.enable
    then "${certDir}/ca.crt"
    else config.age.secrets.nebula-ca.path;
  certPath =
    if cfg.dynamicCerts.enable
    then "${certDir}/cert.crt"
    else config.age.secrets.nebula-cert.path;
  keyPath =
    if cfg.dynamicCerts.enable
    then "${certDir}/cert.key"
    else config.age.secrets.nebula-key.path;

  # Cert fetch script for dynamic mode
  fetchScript = pkgs.writeShellScript "nebula-cert-fetch" ''
    set -euo pipefail

    SERVICE_URL="${cfg.dynamicCerts.serviceUrl}"
    TOKEN_FILE="${config.age.secrets.nebula-token.path}"
    OUTPUT_DIR="${certDir}"

    TOKEN=$(cat "$TOKEN_FILE")

    mkdir -p "$OUTPUT_DIR"

    # Try to fetch new cert from signing service
    if RESPONSE=$(${pkgs.curl}/bin/curl -sf \
        --connect-timeout 10 \
        --max-time 30 \
        -H "Authorization: Bearer $TOKEN" \
        -X POST \
        "$SERVICE_URL/v1/sign"); then

      # Write to temp files for atomic update
      echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.ca' > "$OUTPUT_DIR/ca.crt.tmp"
      echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.cert' > "$OUTPUT_DIR/cert.crt.tmp"
      echo "$RESPONSE" | ${pkgs.jq}/bin/jq -r '.key' > "$OUTPUT_DIR/cert.key.tmp"

      # Verify files aren't empty
      for f in ca.crt.tmp cert.crt.tmp cert.key.tmp; do
        if [ ! -s "$OUTPUT_DIR/$f" ]; then
          echo "ERROR: Empty cert file: $f"
          rm -f "$OUTPUT_DIR"/*.tmp
          exit 1
        fi
      done

      # Atomic move
      mv "$OUTPUT_DIR/ca.crt.tmp" "$OUTPUT_DIR/ca.crt"
      mv "$OUTPUT_DIR/cert.crt.tmp" "$OUTPUT_DIR/cert.crt"
      mv "$OUTPUT_DIR/cert.key.tmp" "$OUTPUT_DIR/cert.key"

      # Set permissions for nebula service
      chmod 644 "$OUTPUT_DIR/ca.crt" "$OUTPUT_DIR/cert.crt"
      chmod 600 "$OUTPUT_DIR/cert.key"
      chown nebula-mesh:nebula-mesh "$OUTPUT_DIR/ca.crt" "$OUTPUT_DIR/cert.crt" "$OUTPUT_DIR/cert.key"

      echo "Successfully fetched new certificate from $SERVICE_URL"
    else
      # Check if we have a cached cert from a previous fetch
      if [ -f "$OUTPUT_DIR/cert.crt" ]; then
        echo "WARNING: Signing service unreachable, using cached certificate"
      else
        echo "ERROR: Signing service unreachable and no cached certificate available"
        exit 1
      fi
    fi
  '';
in {
  options.kimb.nebula = {
    enable = mkEnableOption "Nebula mesh network";

    dynamicCerts = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Fetch certificates dynamically from a signing service instead
          of using static agenix-encrypted certs.

          When enabled, this host needs a nebula-<hostname>-token.age secret
          containing its bearer token for the signing service.
        '';
      };

      serviceUrl = mkOption {
        type = types.str;
        default = (registry.networks.nebula.certService or {}).url or "https://certs.kimb.dev";
        description = "URL of the cert signing service";
      };

      refreshInterval = mkOption {
        type = types.str;
        default = "daily";
        description = ''
          Systemd calendar expression for cert refresh.
          Certs are valid for 48h by default, so daily refresh
          gives a 24h buffer if the service is temporarily unavailable.
        '';
      };
    };

    extraInboundRules = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "Additional inbound firewall rules for this host";
      example = [
        {
          port = 8080;
          proto = "tcp";
          host = "any";
        }
      ];
    };

    openToPersonalDevices = mkOption {
      type = types.bool;
      default = false;
      description = "Allow all ports from desktops and laptops groups";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # === Common config (both modes) ===
    {
      # Nebula mesh network
      services.nebula.networks.mesh = {
        enable = true;
        inherit isLighthouse;

        ca = caPath;
        cert = certPath;
        key = keyPath;

        lighthouses = lighthouseIps;
        staticHostMap = staticHosts;

        settings = {
          punchy = {
            punch = true;
            respond = true;
          };

          # Prefer direct LAN connections over relay/lighthouse routing
          local_range = registry.networks.lan.subnet;
          preferred_ranges = [registry.networks.lan.subnet];

          relay = {
            relays = relayIps;
            am_relay = isRelay;
            use_relays = true;
          };

          # Periodic LAN route checking (helps mobile devices rediscover LAN)
          routines = {
            local_range_check_interval = 30;
          };

          tun = {
            disabled = false;
            dev = "nebula1";
          };

          logging.level = "info";
        };

        firewall = {
          outbound = [
            {
              port = "any";
              proto = "any";
              host = "any";
            }
          ];

          inbound =
            [
              # ICMP from anywhere
              {
                port = "any";
                proto = "icmp";
                host = "any";
              }
              # SSH from anywhere
              {
                port = 22;
                proto = "tcp";
                host = "any";
              }
            ]
            # Optional: open all ports to personal devices
            # Note: separate rules for OR logic (groups = AND, multiple rules = OR)
            ++ optionals cfg.openToPersonalDevices [
              {
                port = "any";
                proto = "any";
                group = "desktops";
              }
              {
                port = "any";
                proto = "any";
                group = "laptops";
              }
              {
                port = "any";
                proto = "any";
                group = "mobile";
              }
            ]
            # Host-specific rules
            ++ cfg.extraInboundRules;
        };
      };

      # Open firewall for Nebula
      networking.firewall.allowedUDPPorts = [4242];
    }

    # === Static cert mode (agenix) ===
    (mkIf (!cfg.dynamicCerts.enable) {
      age.secrets = {
        nebula-ca = {
          file = ../secrets/nebula-ca.age;
          path = "/etc/nebula/ca.crt";
          owner = "nebula-mesh";
          group = "nebula-mesh";
          mode = "0644";
        };

        nebula-cert = {
          file = ../secrets/nebula-${hostname}-cert.age;
          path = "/etc/nebula/${hostname}.crt";
          owner = "nebula-mesh";
          group = "nebula-mesh";
          mode = "0644";
        };

        nebula-key = {
          file = ../secrets/nebula-${hostname}-key.age;
          path = "/etc/nebula/${hostname}.key";
          owner = "nebula-mesh";
          group = "nebula-mesh";
          mode = "0600";
        };
      };

      # Ensure Nebula starts after agenix
      systemd.services."nebula@mesh" = {
        after = ["agenix.service"];
        wants = ["agenix.service"];
      };
    })

    # === Dynamic cert mode (signing service) ===
    (mkIf cfg.dynamicCerts.enable {
      # Token secret for authenticating with the signing service
      age.secrets.nebula-token = {
        file = ../secrets/nebula-${hostname}-token.age;
        mode = "0400";
      };

      # Cert fetch service (runs at boot before nebula, and on timer)
      systemd.services.nebula-cert-fetch = {
        description = "Fetch Nebula certificate from signing service";
        after = ["network-online.target" "agenix.service"];
        wants = ["network-online.target" "agenix.service"];
        before = ["nebula@mesh.service"];
        requiredBy = ["nebula@mesh.service"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = fetchScript;
          StateDirectory = "nebula-dynamic";
        };
      };

      # Periodic cert refresh timer
      systemd.services.nebula-cert-refresh = {
        description = "Refresh Nebula certificate from signing service";
        after = ["network-online.target"];
        wants = ["network-online.target"];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = fetchScript;
          # Restart nebula to pick up new cert (try-restart = only if already running)
          ExecStartPost = "+${pkgs.systemd}/bin/systemctl try-restart nebula@mesh.service";
        };
      };

      systemd.timers.nebula-cert-refresh = {
        description = "Periodic Nebula certificate refresh";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = cfg.dynamicCerts.refreshInterval;
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
      };

      # Nebula waits for cert fetch instead of agenix
      systemd.services."nebula@mesh" = {
        after = ["nebula-cert-fetch.service"];
        wants = ["nebula-cert-fetch.service"];
      };
    })
  ]);
}
