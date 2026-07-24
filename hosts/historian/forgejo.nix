# Forgejo — the fleet's Nebula-only git forge (#forge standup).
#
# This is the authoring/pull-request surface for the bridge crew: officers
# propose, the Lord-Captain reviews + merges here instead of GitHub. GitHub
# stays the nix-fetch remote (systems-flake's OWN flake inputs are NEVER
# repointed at the forge — that's a bootstrap-cycle trap: historian hosts
# the forge, so pointing its own inputs here is a circular cold-start
# dependency). See 40k_bridge/docs/SELF_HOSTED_FORGE.md.
#
# Exposure model:
#   - HTTP (3000) + built-in SSH (2222) bind to the Nebula IP 10.100.0.10
#     ONLY, never 0.0.0.0 — so nothing listens on eno1 (WAN/LAN-safe by
#     binding, not by firewall hope).
#   - Personal devices (desktops/laptops/mobile) reach both ports via
#     kimb.nebula.openToPersonalDevices (historian already sets this).
#   - rich-evans (a *server*, not a personal device) reaches HTTP 3000 for
#     forge API calls via the one extraInboundRule in configuration.nix.
#   - Host firewall deliberately does NOT open 3000/2222 on eno1.
#
# Single-user model: DISABLE_REGISTRATION + REQUIRE_SIGNIN_VIEW + one admin
# account created out-of-band (`forgejo admin user create --admin` after
# first apply; password -> Bitwarden note, NEVER in the nix store/git).
# Bots authenticate with per-bot scoped APPLICATION TOKENS (REST API) + the
# same mccartykim account SSH key re-registered against the forge user (git
# push over the built-in SSH :2222). No SSO: Nebula membership is the first
# auth factor, forge login the second.
{
  config,
  lib,
  pkgs,
  ...
}: {
  services.forgejo = {
    enable = true;

    # Host-local disk, NOT syncthing — forge state must not ride the
    # syncthing->git corruption path (see systems-flake memory).
    stateDir = "/var/lib/forgejo";

    database.type = "sqlite3";

    lfs.enable = true;

    settings = {
      server = {
        # Nebula-only bind — the hardening pin. Never 0.0.0.0.
        HTTP_ADDR = "10.100.0.10";
        HTTP_PORT = 3000;
        DOMAIN = "10.100.0.10";
        ROOT_URL = "http://10.100.0.10:3000/";

        # Built-in SSH server, isolated from the host sshd (:22). The scribe
        # pushes from localhost; the Lord-Captain clones from a desktop over
        # Nebula. Bind to the Nebula IP so it never touches eno1.
        START_SSH_SERVER = true;
        SSH_DOMAIN = "10.100.0.10";
        SSH_PORT = 2222;
        SSH_LISTEN_PORT = 2222;
        SSH_LISTEN_HOST = "10.100.0.10";
      };

      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
      };

      repository = {
        # Push-to-create: the bridge-scribe's sync timer (every 10 min) pushes
        # refs/heads/* to the forge for every repo in its REPOS allowlist. With
        # this on, a repo that does not yet exist on the forge is auto-created
        # under the pushing user (kimb, via the shared account deploy key) on
        # first push — so landing a new officer repo in REPOS seeds the forge
        # with no manual `POST /api/v1/user/repos` (which the narrow forge-bot
        # token cannot do: it lacks write:user). Nebula-only + single admin
        # user, so the open-create surface is just the scribe's own push path.
        ENABLE_PUSH_CREATE_USER = true;
      };

      # Quiet the default telemetry; this is a private fleet forge.
      other.SHOW_FOOTER_VERSION = false;
    };
  };
}