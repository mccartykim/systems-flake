# Tor client with bridge support for bypassing network restrictions
# Useful when behind restrictive firewalls that block direct Tor connections
#
# For environments with HTTP proxies, use the meek transport with:
#   transport = "meek_lite";
#   upstreamSocksProxy = "127.0.0.1:1080"; # gost SOCKS5 proxy
# And run gost to convert HTTP proxy to SOCKS5:
#   gost -L socks5://:1080 -F "http://user:pass@proxy:port"
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.kimb.torClient;
in {
  options.kimb.torClient = {
    enable = mkEnableOption "Tor client with bridge support";

    transport = mkOption {
      type = types.enum ["obfs4" "meek_lite" "snowflake"];
      default = "obfs4";
      description = ''
        Pluggable transport to use:
        - obfs4: Obfuscated traffic, works on most networks
        - meek_lite: Domain fronting through CDN, works through HTTP proxies
        - snowflake: WebRTC-based, good for highly censored networks
      '';
    };

    upstreamSocksProxy = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Upstream SOCKS5 proxy for Tor to use (e.g., "127.0.0.1:1080").
        Useful when behind an HTTP proxy - run gost to convert:
        gost -L socks5://:1080 -F "http://user:pass@proxy:port"
      '';
      example = "127.0.0.1:1080";
    };

    useBridges = mkOption {
      type = types.bool;
      default = true;
      description = "Use bridges to connect to the Tor network (recommended for restrictive networks)";
    };

    bridges = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of bridge lines. If empty and useBridges is true, will use built-in bridges.
        Get bridges from https://bridges.torproject.org/ or email bridges@torproject.org
      '';
      example = [
        "obfs4 192.0.2.1:443 FINGERPRINT cert=CERT iat-mode=0"
      ];
    };

    socksPort = mkOption {
      type = types.port;
      default = 9050;
      description = "SOCKS proxy port for Tor";
    };

    dnsPort = mkOption {
      type = types.port;
      default = 9053;
      description = "DNS port for resolving via Tor";
    };

    transparentProxy = mkOption {
      type = types.bool;
      default = false;
      description = "Enable transparent proxying (requires additional firewall rules)";
    };

    transparentPort = mkOption {
      type = types.port;
      default = 9040;
      description = "Port for transparent proxy";
    };
  };

  config = mkIf cfg.enable {
    # Tor service configuration
    services.tor = {
      enable = true;
      client.enable = true;

      settings = {
        # SOCKS proxy configuration
        SOCKSPort = [
          {
            port = cfg.socksPort;
            IsolateDestAddr = true;
          }
        ];

        # DNS resolution via Tor
        DNSPort = cfg.dnsPort;
        AutomapHostsOnResolve = true;
        AutomapHostsSuffixes = [".onion" ".exit"];

        # Bridge configuration
        UseBridges = cfg.useBridges;

        # Client-specific settings
        ClientOnly = true;

        # Pluggable transport configuration based on selected transport
        ClientTransportPlugin =
          if cfg.transport == "meek_lite" then
            "meek_lite exec ${pkgs.obfs4}/bin/lyrebird"
          else if cfg.transport == "snowflake" then
            "snowflake exec ${pkgs.obfs4}/bin/lyrebird"
          else
            "obfs4 exec ${pkgs.obfs4}/bin/lyrebird";
      }
      # Upstream SOCKS proxy (for HTTP proxy environments)
      // optionalAttrs (cfg.upstreamSocksProxy != null) {
        Socks5Proxy = cfg.upstreamSocksProxy;
      }
      // optionalAttrs (cfg.useBridges && cfg.bridges != []) {
        # Use provided bridges
        Bridge = cfg.bridges;
      }
      // optionalAttrs (cfg.useBridges && cfg.bridges == [] && cfg.transport == "obfs4") {
        # Built-in obfs4 bridges on common ports (80, 443)
        Bridge = [
          "obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=0"
          "obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1"
          "obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1"
          "obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0"
        ];
      }
      // optionalAttrs (cfg.useBridges && cfg.bridges == [] && cfg.transport == "meek_lite") {
        # Built-in meek bridge with domain fronting (works through HTTP proxies)
        Bridge = [
          "meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN"
        ];
      }
      // optionalAttrs (cfg.useBridges && cfg.bridges == [] && cfg.transport == "snowflake") {
        # Built-in snowflake bridges
        Bridge = [
          "snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=www.cdn77.com ice=stun:stun.l.google.com:19302 utls-imitate=hellorandomizedalpn"
        ];
      }
      // optionalAttrs cfg.transparentProxy {
        TransPort = [
          {
            addr = "127.0.0.1";
            port = cfg.transparentPort;
          }
        ];
      };
    };

    # Install torsocks and related tools
    environment.systemPackages = with pkgs; [
      torsocks
      obfs4 # Pluggable transport (lyrebird)
      tor # CLI tools
    ]
    # Add gost for HTTP proxy environments
    ++ optional (cfg.upstreamSocksProxy != null) pkgs.gost;

    # Environment variables for torsocks
    environment.sessionVariables = {
      # Default SOCKS proxy for curl/wget when using torsocks
      TORSOCKS_TOR_ADDRESS = "127.0.0.1";
      TORSOCKS_TOR_PORT = toString cfg.socksPort;
    };

    # Shell aliases for convenience
    programs.bash.interactiveShellInit = ''
      # Tor aliases
      alias torify='torsocks'
      alias tor-curl='torsocks curl'
      alias tor-wget='torsocks wget'
    '';

    programs.fish.interactiveShellInit = ''
      # Tor aliases
      alias torify='torsocks'
      alias tor-curl='torsocks curl'
      alias tor-wget='torsocks wget'
    '';

    # Systemd service overrides for better reliability
    systemd.services.tor = {
      # Retry on failure
      serviceConfig = {
        Restart = "always";
        RestartSec = "10s";
      };
    };
  };
}
