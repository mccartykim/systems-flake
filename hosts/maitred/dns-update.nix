# Migrated DNS configuration using kimb-services options
{ config, lib, ... }:

let
  cfg = config.kimb;
  
  # Get all enabled service domains that need DNS records
  enabledServiceDomains = lib.attrValues (
    lib.mapAttrs (name: service: "${service.subdomain}.${cfg.domain}")
    (lib.filterAttrs (name: service: service.enable && service.publicAccess) cfg.services)
  );
  
  # All domains that need DNS records (root domain + enabled services)
  allDomains = [ cfg.domain ] ++ enabledServiceDomains;
  
  # Generate Cloudflare provider configurations for inadyn
  generateCloudflareProviders = lib.imap0 (i: domain: ''
    provider cloudflare.com:${toString (i + 1)} {
        username = ${cfg.domain}
        password = $token
        hostname = "${domain}"
        ttl = ${toString cfg.dns.ttl}
        proxied = false
    }
  '') allDomains;

in {
  # Dynamic DNS updates (only if we have enabled services)
  services.inadyn = lib.mkIf (cfg.computed.enabledServices != {}) {
    enable = true;
    configFile = "/etc/inadyn/inadyn.conf";
  };

  # Generate inadyn config with Cloudflare API token
  system.activationScripts.inadyn-config = lib.mkIf (cfg.computed.enabledServices != {}) (
    lib.stringAfter ["agenix"] ''
      token=$(cat /run/secrets/cloudflare-api-token)
      mkdir -p /etc/inadyn
      cat > /etc/inadyn/inadyn.conf << EOF
      period = ${toString cfg.dns.updatePeriod}

      ${lib.concatStrings generateCloudflareProviders}
      EOF
      chmod 600 /etc/inadyn/inadyn.conf
    ''
  );

  # Local split-brain DNS with Unbound
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "0.0.0.0" ];
        access-control = [
          "127.0.0.0/8 allow"
          "192.168.69.0/24 allow"    # LAN
          "192.168.100.0/24 allow"   # Container network
          "10.100.0.0/16 allow"      # Nebula mesh
        ];
        
        # Local DNS records - all services resolve to reverse proxy for LAN clients
        local-data = lib.mkIf (cfg.computed.enabledServices != {}) (
          map (domain: "\"${domain}. A ${cfg.networks.reverseProxyIP}\"") allDomains
        );
      };
      
      forward-zone = [
        {
          name = ".";
          forward-addr = cfg.dns.servers.fallback;
        }
      ];
    };
  };
}