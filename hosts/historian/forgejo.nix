# Forgejo forge on historian — Nebula-only self-hosted git surface for the
# bridge-crew bots (#110 Phase-2 hosting side). Plain HTTP + built-in SSH over
# the WireGuard-encrypted Nebula mesh: no TLS, no reverse proxy, no public URL
# (per docs/FORGE_HOSTING_BRIEF.md — public exposure is deliberately deferred).
# Single-user (registration off), sqlite, no CI/runners. Backup is
# NON-OPTIONAL: services.forgejo.dump (logical) + a pre-backup consistent
# SQLite copy wired into the existing restic job (a hot restic read of a live
# SQLite db is not guaranteed crash-consistent).
#
# Option names verified against nixpkgs 26.11 services/misc/forgejo.nix.
# Package is left at the module default (pkgs.forgejo-lts) — the version
# nixpkgs supports best via its options; no manual override to maintain.
{
  config,
  lib,
  pkgs,
  ...
}: {
  services.forgejo = {
    enable = true;
    # Package left at the module default (pkgs.forgejo-lts) — the version
    # nixpkgs supports best via its options; no manual override to maintain.
    database.type = "sqlite3"; # single-user, no external DB
    lfs.enable = false; # crew repos are plain git
    useWizard = false; # declarative app.ini

    # Non-optional logical backup (DB + repos + custom conf, secrets redacted).
    # Lands in /var/lib/forgejo/dump (under /var/lib, already in kimb.restic
    # paths). type default is "zip"; tar.gz is restic-friendly.
    dump = {
      enable = true;
      type = "tar.gz";
    };

    settings = {
      server = {
        PROTOCOL = "http"; # plain HTTP over Nebula (WireGuard = in-transit crypto)
        HTTP_ADDR = "10.100.0.10"; # bind Nebula-only, NOT 0.0.0.0
        HTTP_PORT = 3000;
        DOMAIN = "10.100.0.10";
        ROOT_URL = "http://10.100.0.10:3000/";
        LOCAL_ROOT_URL = "http://10.100.0.10:3000/"; # pin internal callbacks
        OFFLINE_MODE = true; # no CDN/gravatar fetches over the Nebula-only path
        LANDING_PAGE = "signin";

        # Built-in SSH server — off host sshd:22 (which is already the
        # bridge-scribe forced-command target + the distributed-builds
        # nix-daemon key). SSH_LISTEN_HOST defaults to 0.0.0.0 and would leak
        # to the LAN, so bind it Nebula-only alongside HTTP_ADDR.
        START_SSH_SERVER = true;
        SSH_DOMAIN = "10.100.0.10";
        SSH_PORT = 2222; # displayed clone port
        SSH_LISTEN_PORT = 2222; # actual bind port
        SSH_LISTEN_HOST = "10.100.0.10";
        DISABLE_SSH = false;
      };

      service = {
        DISABLE_REGISTRATION = true; # single Lord-Captain, no signups
        REQUIRE_SIGNIN_VIEW = true; # hide content behind login (defense-in-depth)
      };

      mirror = {
        ENABLED = true; # pull-mirror (crew repos mirror GitHub)
        ENABLE_PUSH_MIRROR = true; # default FALSE — on-merge push main -> GitHub
        DEFAULT_INTERVAL = "8h";
        MIN_INTERVAL = "10m";
      };

      actions.ENABLED = false; # no CI/runners (key is ENABLED, not DISABLED)
      log.LEVEL = "Info";
      session.COOKIE_SECURE = false; # LEAVE false — plain http; true drops cookies
      # security.INSTALL_LOCK/SECRET_KEY/INTERNAL_TOKEN/oauth2.JWT_SECRET are
      # auto-set by the module + forgejo-secrets.service on first boot. Do NOT
      # set them here, and do NOT route the bot token through
      # services.forgejo.secrets — it is an agenix secret consumed outside
      # forgejo (see configuration.nix age.secrets.forge-bot-token).
    };
  };

  # Pre-backup consistent SQLite copy via the online-backup API (safe on a
  # live WAL db; a raw restic read of a live .db is NOT guaranteed
  # crash-consistent). Runs as root (restic backup service default user)
  # before each restic run; the [ -f ] guard makes it a no-op on hosts without
  # forgejo, so it is safe to keep if this file is ever shared. Merges into
  # the "home" backup created by modules/restic-backup.nix +
  # restic-b2-backup-flake. No new restic path/exclude is needed: /var/lib is
  # already in services.resticB2.paths and /var/lib/forgejo is not excluded.
  services.restic.backups."home".backupPrepareCommand = ''
    [ -f /var/lib/forgejo/data/forgejo.db ] || exit 0
    install -d -m 0750 -o forgejo -g forgejo /var/lib/forgejo/dump
    ${pkgs.sqlite}/bin/sqlite3 /var/lib/forgejo/data/forgejo.db \
      ".backup '/var/lib/forgejo/dump/forgejo.db.consistent'"
    chown forgejo:forgejo /var/lib/forgejo/dump/forgejo.db.consistent
    chmod 0640 /var/lib/forgejo/dump/forgejo.db.consistent
  '';
}
