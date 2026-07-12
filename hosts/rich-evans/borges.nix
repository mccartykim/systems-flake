# Borges — EPUB-first ebook server, running as a host service on rich-evans.
# Same pattern as knitwork.nix: a flake-input-backed NixOS module run as a host
# service (NOT a maitred container like blog). The borges binary serves the
# OPDS-1 catalog + kosync reading-position sync + the in-browser reader over
# HTTP, with its own accounts / device PINs / sessions.
#
# Caddy on maitred terminates TLS for borges.kimb.dev and reverse-proxies to
# this host over Nebula. maitred runs a socat forwarder (containerBridge:7171
# → 10.100.0.40:7171, see hosts/maitred/configuration.nix `mkProxyService`)
# driven by the duplicate `borges` entry in services/default.nix under the
# maitred bucket. borges does its own HTTP Basic + session auth, so the vhost
# uses auth = "none" — no Authelia gate, which would break the e-reader clients
# (KOReader/CrossPoint speak Basic + x-auth-user, not an interactive SSO flow).
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: let
  borges = config.kimb.services.borges;
in {
  # borges's NixOS module is portable: it does not reference flake-self. The
  # caller sets services.borges.package to the flake package.
  imports = [inputs.borges.nixosModules.borges];

  services.borges = lib.mkIf borges.enable {
    enable = true;
    package = inputs.borges.packages.${pkgs.system}.default;
    # Bind all interfaces so maitred's socat can reach us over Nebula
    # (10.100.0.40). The host firewall already trusts nebula1, so no iptables
    # rule is needed — same as knitwork.nix.
    listenAddress = "0.0.0.0:${toString borges.port}";
    # Book library on the external Seagate. Drop EPUBs/CBZ here (or symlink a
    # Syncthing dir to this path); the borges user must be able to read it.
    # See the borges.nix deploy notes — confirm/adjust this path to where your
    # books actually live.
    libraryRoots = ["/mnt/seagate/borges/lib"];
    databasePath = "/var/lib/borges/borges.db";
    adminUser = "admin";
    # maitred's socat forwarder is the immediate peer borges sees
    # (RemoteAddr = 10.100.0.50, maitred's Nebula IP). Trusting its
    # X-Forwarded-For (set by Caddy, passed through raw by socat) lets the
    # auth-failure limiter key on each device's real IP instead of collapsing
    # all proxied traffic onto one lockout bucket — which otherwise lets
    # internet scanners 401-ing on non-borges paths lock out every real device.
    trustedProxies = ["10.100.0.50"];
    # Secret env (age-encrypted to rich-evans's SSH host key + bootstrap, see
    # secrets/secrets.nix): BORGES_ADMIN_PASS (required), BORGES_APP_PASS_KEY
    # (pepper for app-passwords/sessions — outside the DB so a DB leak alone
    # can't forge a session or brute-force a PIN), BORGES_BASE_URL
    # (https://borges.kimb.dev → Secure session cookie). The borges service
    # runs as the borges user (module sets User=borges), so the decrypted file
    # is borges-owned 0400.
    environmentFile = config.age.secrets.borges-env.path;
  };

  age.secrets.borges-env = {
    file = ../../secrets/borges-env.age;
    mode = "0400";
    owner = "borges";
    group = "borges";
  };

  # Let maitred's socat proxy reach borges over Nebula (port 7171). Host
  # firewall already trusts nebula1, so no iptables rule is needed — same as
  # knitwork.nix.
  kimb.nebula.extraInboundRules = lib.mkIf borges.enable [
    {
      port = borges.port;
      proto = "tcp";
      host = "maitred";
    }
  ];
}