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
  pkgs,
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

  # The cloudflare-ddns module's activation writes /etc/inadyn/inadyn.conf as
  # root:root 0600 (mkdir+cat+chmod, no chown), but the nixpkgs inadyn unit runs
  # as User=inadyn -> it can't read its own config ('Cannot read configuration
  # file', exit 74). maitred dodges this via a pre-existing inadyn-owned file;
  # here the chown runs on each start (the '+' prefix = as root).
  systemd.services.inadyn.serviceConfig.ExecStartPre =
    lib.mkIf cfg.services.reverse-proxy.enable [
      "+${pkgs.coreutils}/bin/chown inadyn:inadyn /etc/inadyn/inadyn.conf"
    ];
}
