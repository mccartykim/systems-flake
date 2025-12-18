# Fire-and-forget containernet integration for NixOS containers
# Use inside container config: imports = [ ../../modules/containernet-container.nix ];
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
with builtins;
let
  cfg = config.kimb.containernet;
in {
  options.kimb.containernet = {
    enable = mkEnableOption "Containernet mesh integration";

    hostAddress = mkOption {
      type = types.str;
      description = "The container's hostAddress (veth peer IP on host side)";
      example = "192.168.100.11";
    };

    tokenPath = mkOption {
      type = types.str;
      default = "/run/containernet/token";
      description = "Path to the bearer token file";
    };

    certServicePort = mkOption {
      type = types.int;
      default = 8444;
      description = "Port for cert service on host";
    };

    lighthousePort = mkOption {
      type = types.int;
      default = 4244;
      description = "Port for containernet lighthouse on host";
    };

    publicLighthouseHosts = mkOption {
      type = types.listOf types.str;
      default = ["kimb.dev:4244" "150.136.155.204:4244"];
      description = "Public lighthouse endpoints for failover";
    };

    lighthouseIps = mkOption {
      type = types.listOf types.str;
      default = ["10.102.0.1" "10.102.0.2"];
      description = "Nebula IPs of lighthouses (maitred + oracle)";
    };

    servicePorts = mkOption {
      type = types.listOf types.int;
      default = [];
      description = "TCP ports to expose on containernet";
    };

    groups = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional groups to request (cert service adds 'containers' by default)";
    };
  };

  config = mkIf cfg.enable (let
    # Derive URLs from hostAddress
    certServiceUrl = "http://${cfg.hostAddress}:${toString cfg.certServicePort}";
    localLighthouse = "${cfg.hostAddress}:${toString cfg.lighthousePort}";
    lighthouseHosts = [localLighthouse] ++ cfg.publicLighthouseHosts;
  in {
    environment.systemPackages = [pkgs.nebula pkgs.curl pkgs.jq];

    # Request cert at boot (not in wantedBy to avoid blocking container startup)
    # nebula-containernet.service pulls this in via Requires
    systemd.services.containernet-cert = {
      description = "Request containernet certificate";
      # NOT in wantedBy - let container reach active state first so post-start runs
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Delay to ensure host post-start has assigned veth IP
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
        ExecStart = pkgs.writeShellScript "request-containernet-cert" ''
          set -euo pipefail
          CERT_DIR=/run/containernet
          mkdir -p "$CERT_DIR"

          [ -f "$CERT_DIR/host.crt" ] && exit 0 # Already have cert

          # Token file is in env format (API_TOKEN=value), extract just the value
          TOKEN=$(grep -oP 'API_TOKEN=\K.*' ${cfg.tokenPath} || cat ${cfg.tokenPath})

          # Retry with exponential backoff: 2s, 4s, 8s, 16s, 32s, 64s
          max_attempts=6
          attempt=1
          delay=2

          while [ $attempt -le $max_attempts ]; do
            echo "Cert allocation attempt $attempt/$max_attempts..."

            if resp=$(${pkgs.curl}/bin/curl -sf --max-time 30 -X POST \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" \
              -d '${builtins.toJSON (if cfg.groups != [] then { groups = cfg.groups; } else {})}' \
              "${certServiceUrl}/containernet/allocate"); then

              if echo "$resp" | ${pkgs.jq}/bin/jq -e '.ca and .cert and .key and .ip' > /dev/null 2>&1; then
                echo "$resp" | ${pkgs.jq}/bin/jq -r '.ca' > "$CERT_DIR/ca.crt"
                echo "$resp" | ${pkgs.jq}/bin/jq -r '.cert' > "$CERT_DIR/host.crt"
                echo "$resp" | ${pkgs.jq}/bin/jq -r '.key' > "$CERT_DIR/host.key"
                echo "$resp" | ${pkgs.jq}/bin/jq -r '.ip' > "$CERT_DIR/ip"
                chmod 600 "$CERT_DIR/host.key"
                echo "Got containernet cert: $(cat $CERT_DIR/ip)"
                exit 0
              else
                echo "Invalid response from cert service"
              fi
            else
              echo "Request failed (attempt $attempt)"
            fi

            if [ $attempt -lt $max_attempts ]; then
              echo "Retrying in ''${delay}s..."
              sleep $delay
              delay=$((delay * 2))
            fi
            attempt=$((attempt + 1))
          done

          echo "ERROR: Failed to get cert after $max_attempts attempts"
          exit 1
        '';
      };
    };

    # Start nebula with obtained cert (started by timer, not blocking boot)
    systemd.services.nebula-containernet = let
      # Build static_host_map as proper attrset
      staticHostMap = listToAttrs (map (ip: {
        name = ip;
        value = lighthouseHosts;
      }) cfg.lighthouseIps);

      # Build inbound firewall rules
      inboundRules = [
        { port = "any"; proto = "icmp"; host = "any"; }
      ] ++ (map (p: { port = p; proto = "tcp"; host = "any"; }) cfg.servicePorts);

      nebulaConfig = {
        pki = {
          ca = "/run/containernet/ca.crt";
          cert = "/run/containernet/host.crt";
          key = "/run/containernet/host.key";
        };
        static_host_map = staticHostMap;
        lighthouse.hosts = cfg.lighthouseIps;
        listen.port = 0;
        tun.dev = "nebula-cnt";
        punchy = { punch = true; respond = true; };
        relay.use_relays = true;
        firewall = {
          outbound = [{ port = "any"; proto = "any"; host = "any"; }];
          inbound = inboundRules;
        };
      };

      configFile = pkgs.writeText "nebula-containernet-config.yml"
        (builtins.toJSON nebulaConfig);
    in {
      description = "Nebula containernet";
      # NOT in wantedBy - started by timer after container is fully up
      after = ["containernet-cert.service"];
      requires = ["containernet-cert.service"];
      serviceConfig = {
        ExecStart = "${pkgs.nebula}/bin/nebula -config ${configFile}";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    networking.firewall.allowedTCPPorts = cfg.servicePorts;

    # Cert renewal timer - renews at 50% lifetime
    systemd.services.containernet-cert-renew = {
      description = "Renew containernet certificate before expiry";
      after = ["containernet-cert.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "renew-containernet-cert" ''
          set -euo pipefail
          CERT_DIR=/run/containernet

          [ ! -f "$CERT_DIR/host.crt" ] && exit 0 # No cert yet

          # Parse cert expiry (nebula-cert print outputs epoch timestamp)
          cert_json=$(${pkgs.nebula}/bin/nebula-cert print -json -path "$CERT_DIR/host.crt")
          not_before=$(echo "$cert_json" | ${pkgs.jq}/bin/jq -r '.details.notBefore')
          not_after=$(echo "$cert_json" | ${pkgs.jq}/bin/jq -r '.details.notAfter')
          now=$(date +%s)

          # Calculate lifetime and 50% threshold
          lifetime=$((not_after - not_before))
          threshold=$((not_before + lifetime / 2))

          if [ "$now" -lt "$threshold" ]; then
            echo "Cert still fresh ($(( (threshold - now) / 3600 ))h until renewal threshold)"
            exit 0
          fi

          echo "Cert past 50% lifetime, renewing..."
          current_ip=$(cat "$CERT_DIR/ip")
          # Token file is in env format (API_TOKEN=value), extract just the value
          TOKEN=$(grep -oP 'API_TOKEN=\K.*' ${cfg.tokenPath} || cat ${cfg.tokenPath})

          # Retry with exponential backoff: 5s, 10s, 20s, 40s, 80s
          max_attempts=5
          attempt=1
          delay=5

          while [ $attempt -le $max_attempts ]; do
            echo "Renewal attempt $attempt/$max_attempts..."

            if resp=$(${pkgs.curl}/bin/curl -sf --max-time 30 -X POST \
              -H "Authorization: Bearer $TOKEN" \
              -H "Content-Type: application/json" \
              -d "{\"current_ip\": \"$current_ip\"}" \
              "${certServiceUrl}/containernet/renew"); then

              # Validate response has required fields
              if echo "$resp" | ${pkgs.jq}/bin/jq -e '.cert and .key' > /dev/null 2>&1; then
                echo "$resp" | ${pkgs.jq}/bin/jq -r '.cert' > "$CERT_DIR/host.crt.new"
                echo "$resp" | ${pkgs.jq}/bin/jq -r '.key' > "$CERT_DIR/host.key.new"

                mv "$CERT_DIR/host.crt.new" "$CERT_DIR/host.crt"
                mv "$CERT_DIR/host.key.new" "$CERT_DIR/host.key"
                chmod 600 "$CERT_DIR/host.key"

                echo "Renewed cert, reloading nebula..."
                systemctl restart nebula-containernet.service
                exit 0
              else
                echo "Invalid response from cert service"
              fi
            else
              echo "Request failed (attempt $attempt)"
            fi

            if [ $attempt -lt $max_attempts ]; then
              echo "Retrying in ''${delay}s..."
              sleep $delay
              delay=$((delay * 2))
            fi
            attempt=$((attempt + 1))
          done

          echo "ERROR: Failed to renew cert after $max_attempts attempts"
          exit 1
        '';
      };
    };

    # Timer to start containernet after container is fully up (post-start complete)
    systemd.timers.containernet-start = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10s"; # Give time for host post-start to assign veth IP
        Unit = "nebula-containernet.service";
      };
    };

    systemd.timers.containernet-cert-renew = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1h"; # First check 1h after boot
        OnUnitActiveSec = "6h"; # Then every 6h
        Persistent = true;
      };
    };
  });
}
