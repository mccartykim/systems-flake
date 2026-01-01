# Tor middle relay - contributing to the Tor network
# Non-exit relay: just passes encrypted traffic, no legal risk
{
  config,
  lib,
  pkgs,
  ...
}: {
  services.tor = {
    enable = true;
    openFirewall = true;
    controlSocket.enable = true;

    relay = {
      enable = true;
      role = "bridge"; # Middle relay, NOT exit
    };

    settings = {
      # Relay identification
      ContactInfo = "kimb@kimb.dev";

      ServerTransportListenAddr = "obfs4 0.0.0.0:24608";

      # Ports - IPv4 only since we don't have IPv6 on this network
      ORPort = [
        {
          port = 24607;
          IPv4Only = true;
        }
      ];
      # DirPort = 9030;  # Uncomment to also serve directory info

      # Bandwidth limiting - generous but won't impact streaming/zoom
      # 5 MB/s = 40 Mbps sustained, plenty of headroom on gigabit
      RelayBandwidthRate = "10 MBytes";
      RelayBandwidthBurst = "20 MBytes";

      # Accounting - optional monthly cap (unlimited for now)
      # AccountingMax = "1 TBytes";
      # AccountingStart = "month 1 00:00";

      # Performance tuning for low-power CPU
      NumCPUs = 2; # Don't use all 4 cores
    };
  };
}
