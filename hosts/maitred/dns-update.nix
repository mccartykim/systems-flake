# Migrated DNS configuration using kimb-services options
{
  config,
  lib,
  ...
}: let
  cfg = config.kimb;

  # Only update root domain and wildcard - wildcard covers all subdomains
  allDomains = [cfg.domain "*.${cfg.domain}"];

  # Generate Cloudflare provider configurations for inadyn
  generateCloudflareProviders =
    lib.imap0 (i: domain: ''
      provider cloudflare.com:${toString (i + 1)} {
          username = ${cfg.domain}
          password = $token
          hostname = "${domain}"
          ttl = ${toString cfg.dns.ttl}
          proxied = false
      }
    '')
    allDomains;
in {
  # Dynamic DNS updates (only if we have enabled services)
  services.inadyn = lib.mkIf (cfg.computed.enabledServices != {}) {
    enable = true;
    configFile = "/etc/inadyn/inadyn.conf";
  };

  # Ensure inadyn starts after DNS is available (unbound provides nss-lookup.target)
  systemd.services.inadyn = lib.mkIf (cfg.computed.enabledServices != {}) {
    after = ["nss-lookup.target"];
    wants = ["nss-lookup.target"];
  };

  # Generate inadyn config with Cloudflare API token
  system.activationScripts.inadyn-config = lib.mkIf (cfg.computed.enabledServices != {}) (
    lib.stringAfter ["agenix"] ''
      token=$(cat ${config.age.secrets.cloudflare-api-token.path})
      mkdir -p /etc/inadyn
      cat > /etc/inadyn/inadyn.conf << EOF
      period = ${toString cfg.dns.updatePeriod}

      ${lib.concatStrings generateCloudflareProviders}
      EOF
      chmod 600 /etc/inadyn/inadyn.conf
    ''
  );
}
