# Dynamic DNS (Cloudflare/inadyn) — the a3j.8.2 migration from maitred.
#
# Host service on historian. The agenix cloudflare-api-token is pre-keyed for
# historian (verified to decrypt). Because historian sits behind maitred's NAT,
# its outbound IP is the same public WAN IP, so inadyn reports the correct
# address. Gated on historian's OWN bucket; during (a) maitred keeps its copy
# (both updating the same records with the same IP is harmless) until the flip.
{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.kimb;
in {
  imports = [
    inputs.cloudflare-ddns.nixosModules.default
  ];

  age.secrets.cloudflare-api-token = lib.mkIf cfg.services.reverse-proxy.enable {
    file = ../../secrets/cloudflare-api-token.age;
    mode = "0400";
  };

  services.cloudflareDdns = lib.mkIf cfg.services.reverse-proxy.enable {
    enable = true;
    domain = cfg.domain;
    extraHostnames = ["*.${cfg.domain}"];
    apiTokenFile = config.age.secrets.cloudflare-api-token.path;
    inherit (cfg.dns) ttl updatePeriod;
  };
}
