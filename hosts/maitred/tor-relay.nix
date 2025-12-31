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

    relay = {
      enable = true;
      role = "relay"; # Middle relay, NOT exit
    };

    settings = {
      # Relay identification
      Nickname = "maitredrelay";
      ContactInfo = "kimb@kimb.dev";

      # Ports - IPv4 only since we don't have IPv6 on this network
      ORPort = [
        {
          port = 9001;
          IPv4Only = true;
        }
      ];
      # DirPort = 9030;  # Uncomment to also serve directory info

      # Control port for nyx monitoring (access via SSH)
      ControlPort = 9051;
      CookieAuthentication = true;

      # Bandwidth limiting - generous but won't impact streaming/zoom
      # 5 MB/s = 40 Mbps sustained, plenty of headroom on gigabit
      RelayBandwidthRate = "5 MBytes";
      RelayBandwidthBurst = "10 MBytes";

      # Accounting - optional monthly cap (unlimited for now)
      # AccountingMax = "1 TBytes";
      # AccountingStart = "month 1 00:00";

      # Performance tuning for low-power CPU
      NumCPUs = 2; # Don't use all 4 cores
    };
  };

  # Firewall rules (openFirewall should handle this, but explicit is good)
  networking.firewall.allowedTCPPorts = [9001];

  # Allow Tor control port from Nebula network
  kimb.nebula.extraInboundRules = [
    {
      port = 9051;
      proto = "tcp";
      host = "any";
    }
  ];
}
