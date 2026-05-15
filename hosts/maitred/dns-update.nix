# Personalization layer for the cloudflare-ddns flake module.
# Wires the generic services.cloudflareDdns to kimb-services state:
# only enables inadyn when at least one externally-exposed service is
# defined, uses kimb.domain as the zone, and adds the wildcard subdomain
# so all *.<domain> records track the same public IP.
{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.kimb;
in {
  imports = [
    inputs.agenix.nixosModules.default
    inputs.cloudflare-ddns.nixosModules.default
  ];

  age.secrets.cloudflare-api-token = {
    file = "${inputs.secretsFlake}/secrets/cloudflare-api-token.age";
    mode = "0400";
  };

  services.cloudflareDdns = lib.mkIf (cfg.computed.enabledServices != {}) {
    enable = true;
    domain = cfg.domain;
    extraHostnames = ["*.${cfg.domain}"];
    apiTokenFile = config.age.secrets.cloudflare-api-token.path;
    inherit (cfg.dns) ttl updatePeriod;
  };
}
