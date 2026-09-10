# Borges — EPUB-first ebook server, running as a host service on historian.
# Ported from hosts/rich-evans/borges.nix at a3j.5: a flake-input-backed
# NixOS module run as a host service (same shape as on rich-evans — the
# source pattern is preserved exactly; an nspawn/domU lift is a later
# option, not a migration variable). The borges binary serves the OPDS-1
# catalog + kosync reading-position sync + the in-browser reader over HTTP,
# with its own accounts / device PINs / sessions.
#
# Caddy on maitred terminates TLS for borges.kimb.dev and reverse-proxies to
# this host over Nebula. maitred runs a socat forwarder (containerBridge:7171
# → 10.100.0.10:7171, see hosts/maitred/configuration.nix `mkProxyService`)
# driven by the duplicate `borges` entry in services/default.nix under the
# maitred bucket — repointed from rich-evans to historian at the a3j.5
# cutover. borges does its own HTTP Basic + session auth, so the vhost uses
# auth = "none" — no Authelia gate, which would break the e-reader clients
# (KOReader/CrossPoint speak Basic + x-auth-user, not an interactive SSO flow).
#
# Library on the seagate — read via the /mnt/media-drive NFS automount
# (10.100.0.40:/, read-only) until a3j.4 physically moves the drive to this
# box. Path-preserved: when the drive lands it mounts at the SAME
# /mnt/media-drive path, so this config is untouched by a3j.4. The scanner
# only READS library roots (ingest writes to the SQLite DB in /var/lib/
# borges), so the ro NFS export is fine; new-book drops continue to happen
# on rich-evans's local /mnt/seagate/borges/lib (the single-writer
# discipline) until the drive moves.
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
    # (10.100.0.10). The host firewall already trusts nebula1, so the
    # kimb.nebula extraInboundRule below is the only gate.
    listenAddress = "0.0.0.0:${toString borges.port}";
    # Book library on the seagate (NFS-automounted at the a3j.4 path-
    # preserved mountpoint; see header comment).
    libraryRoots = ["/mnt/media-drive/borges/lib"];
    databasePath = "/var/lib/borges/borges.db";
    adminUser = "admin";
    # maitred's socat forwarder is the immediate peer borges sees
    # (RemoteAddr = 10.100.0.50, maitred's Nebula IP) — unchanged from the
    # rich-evans deployment. Trusting its X-Forwarded-For (set by Caddy,
    # passed through raw by socat) lets the auth-failure limiter key on each
    # device's real IP instead of collapsing all proxied traffic onto one
    # lockout bucket.
    trustedProxies = ["10.100.0.50"];
    # Secret env (age-encrypted to the fleet-core recipient set — rich-evans
    # + historian + bootstrap, see secrets/secrets.nix): BORGES_ADMIN_PASS
    # (required), BORGES_APP_PASS_KEY (pepper for app-passwords/sessions —
    # outside the DB so a DB leak alone can't forge a session or brute-force
    # a PIN), BORGES_BASE_URL (https://borges.kimb.dev → Secure session
    # cookie). The borges service runs as the borges user (module sets
    # User=borges), so the decrypted file is borges-owned 0400.
    environmentFile = config.age.secrets.borges-env.path;

    # Secret declaration lives INSIDE the same mkIf as the service: the
    # decrypted file is chowned to the borges user (see age.secrets below),
    # who only exists once services.borges.enable creates the module's
    # system user — an eager top-level declaration would fail activation
    # with agenixChown: user 'borges' does not exist while enable=false.
  };

  age.secrets.borges-env = lib.mkIf borges.enable {
    file = ../../secrets/borges-env.age;
    mode = "0400";
    owner = "borges";
    group = "borges";
  };

  # Let maitred's socat proxy reach borges over Nebula (port 7171). Host
  # firewall already trusts nebula1, so the nebula ACL rule is the only gate.
  kimb.nebula.extraInboundRules = lib.mkIf borges.enable [
    {
      port = borges.port;
      proto = "tcp";
      host = "maitred";
    }
  ];
}