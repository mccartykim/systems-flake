# Tor client with bridge support for bypassing network restrictions
# Useful when behind restrictive firewalls that block direct Tor connections
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

    useBridges = mkOption {
      type = types.bool;
      default = true;
      description = "Use bridges to connect to the Tor network (recommended for restrictive networks)";
    };

    bridges = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of bridge lines. If empty and useBridges is true, will use built-in obfs4 bridges.
        Get bridges from https://bridges.torproject.org/ or email bridges@torproject.org
        Format: "obfs4 IP:PORT FINGERPRINT cert=CERT iat-mode=0"
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

        # Use pluggable transports
        ClientTransportPlugin = "obfs4 exec ${pkgs.obfs4}/bin/lyrebird";
      }
      // optionalAttrs (cfg.useBridges && cfg.bridges != []) {
        # Use provided bridges
        Bridge = cfg.bridges;
      }
      // optionalAttrs (cfg.useBridges && cfg.bridges == []) {
        # Built-in obfs4 bridges on common ports (80, 443)
        # These are public bridges from Tor Project, may become stale
        # Get fresh ones from https://bridges.torproject.org/
        Bridge = [
          # obfs4 bridges on port 443 (HTTPS port - usually allowed)
          "obfs4 193.11.166.194:443 2D82C2E354D531A68469ADA8F3F5B3B1B6E5FE21 cert=XHo3i3V+U0BG7S8hqzw+UQB7RwU5E1RD0i7nGlwfkLR6K8R7lNGRDTBG3gJgPO4HXG3h+w iat-mode=0"
          "obfs4 85.31.186.98:443 011F2599C0E9B27EE74B353155E244813763C3E5 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3b17+dBdpXqNqVezA8EPiBAXBYJqHWmkhPxKJe5YxE2A iat-mode=0"
          # obfs4 bridges on port 80 (HTTP port - usually allowed)
          "obfs4 209.148.46.65:80 D54D12D25DCECE5C7FC3E07A0583E17D78F70F48 cert=gIIjL5JTHNA8M8Rj8S+R9d8snNaUGP5iBKq5H1w+0V7nLb2B3PYGx5F8Bvx8cVLnDqNhfw iat-mode=0"
          "obfs4 146.57.248.225:80 7A6A6B98BE0EAE24D6A73927AE3FEF0A32D8C685 cert=d6I3BZTGkBTu97TjVB8FGY3R+Y5xF7FKhTU8zp1G8fVULCc5bN5PEu+pMvQBVj9z7T2p7w iat-mode=0"
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

    # Install torsocks for wrapping commands
    environment.systemPackages = with pkgs; [
      torsocks
      obfs4 # Pluggable transport
      tor # CLI tools
    ];

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
