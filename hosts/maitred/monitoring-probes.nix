# Synthetic probes for SRE observability
# Runs on maitred; metrics exported via node_exporter textfile collector.
{
  config,
  lib,
  pkgs,
  ...
}: let
  textfileDir = "/var/lib/prometheus-node-exporter-textfiles";
in {
  # Ensure textfile directory exists
  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 nobody nogroup -"
  ];

  # Ollama liveness probe — hits /api/tags on each ollama host
  systemd.services.ollama-synthetic-probe = {
    description = "Probe ollama liveness on historian and total-eclipse";
    serviceConfig.Type = "oneshot";
    path = [pkgs.curl pkgs.coreutils];
    script = ''
      OUT=${textfileDir}/ollama_probe.prom.tmp
      FINAL=${textfileDir}/ollama_probe.prom

      cat > "$OUT" << 'HEADER'
      # HELP ollama_up Whether ollama /api/tags responded with 200 (1=ok, 0=fail)
      # TYPE ollama_up gauge
      HEADER

      probe() {
        local name=$1 ip=$2
        local status=0
        if curl -sf --max-time 8 "http://$ip:11434/api/tags" >/dev/null 2>&1; then
          status=1
        fi
        echo "ollama_up{host=\"$name\"} $status" >> "$OUT"
      }

      probe historian 10.100.0.10
      probe total-eclipse 10.100.0.6

      mv "$OUT" "$FINAL"
    '';
  };

  systemd.timers.ollama-synthetic-probe = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/2";
      Persistent = true;
    };
  };
}
