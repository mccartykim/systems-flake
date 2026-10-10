# Hermes Agent — fleet AI-agent gateway + backend on historian.
#
# Phase 2 of the hermes→historian migration (docs/hermes-historian-migration-prd.md
# §3.1/§4; design reference: systems-flake-ops skill, references/hermes-on-historian.md).
# One module instance serves all five profiles via the gateway multiplexer:
# profiles are subdirs of a single HERMES_HOME (/var/lib/hermes/.hermes), each
# keeps its own config.yaml/skills/memories/sessions/bot tokens, and activation
# never touches per-profile config (only the top-level config.yaml + .env are
# rendered). Blog-pm, knitwork-pm, facade-decomper, jobcoach, systems-flake-mgr.
#
# Q8 (service identity, PRD §5): the units run as `kimb` — the syncthing/email-digest
# precedent on this host, and the load-bearing reason here: jobcoach writes the
# job-search workspace at /home/kimb/shared_projects/job_search_mk2 →
# /mnt/media-drive/job_search_mk2, which syncthing (User=kimb) owns. Running the
# agent as kimb makes workspace writes just work; a separate `hermes` user would
# need group plumbing into syncthing's file set. createUser=false + our own
# user declaration keeps home-manager's kimb config intact.
#
# Q9 (dashboard exposure): backend.mode = "serve" binds historian.nebula only —
# the desktop app on laptops/phone connects as a Remote gateway (Settings →
# Gateways). Non-loopback bind engages the dashboard auth gate; the stable
# session token comes from agenix (backend.sessionTokenFile, str not path — a
# path literal would copy the secret into the store). The `dashboard` SPA mode
# can be flipped on later without moving state.
{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.services.hermes-agent;
in {
  imports = [inputs.hermes-agent.nixosModules.default];

  # Q8: run the gateway + backend as kimb. The upstream module's createUser
  # path makes a system user with home = stateDir; we instead declare kimb's
  # membership ourselves and point the service at the existing account.
  services.hermes-agent = {
    enable = true;
    user = "kimb";
    group = "users";
    createUser = false;

    stateDir = "/var/lib/hermes";

    # Non-secret config → settings (deep-merged into the TOP-LEVEL config.yaml
    # each activation; per-profile config.yaml files are never touched). Values
    # mirror TE's live top-level config.yaml (verified 2026-10-10).
    settings = {
      telemetry.shared_metrics = {
        enabled = false;
        send = false;
      };
      model = {
        default = "glm-5.3";
        provider = "ollama-cloud";
        base_url = "https://ollama.com/v1";
        api_mode = "chat_completions";
      };
    };

    # Secrets: the top-level .env is rendered from these at activation
    # (REWRITTEN each activation — any pre-existing top-level .env is replaced,
    # so TE's OLLAMA_API_KEY must live here or the first activation drops it).
    # Per-PROFILE .env files are NOT managed by the module and ride over from
    # the rsync (jobcoach: OLLAMA_API_KEY + DISCORD_ALLOWED_USERS, etc.).
    environmentFiles = [
      config.age.secrets.hermes-env.path
    ];

    # Backend for the desktop app's remote-gateway connections. Nebula-only:
    # the auth gate engages automatically on the non-loopback bind; credentials
    # via HERMES_DASHBOARD_BASIC_AUTH_* in the hermes-env secret (documented
    # trusted-LAN provider), stable API session token via the agenix secret.
    backend = {
      mode = "serve";
      host = "historian.nebula";
      port = 9119;
      # historian.nebula resolves via the static nebula host entries; the
      # address exists at boot, but be explicit anyway — a cold boot where
      # nebula starts after the unit would otherwise fail the bind.
      waitFor = "hostname";
      sessionTokenFile = config.age.secrets.hermes-dashboard-session-token.path;
    };

    # Workspace default for tool calls that use a relative path. The canonical
    # job-search tree lives on the media-drive via the per-folder symlink
    # (PRD §3.2 — NOT the superseded whole-drive form).
    workingDirectory = "/var/lib/hermes/workspace";
  };

  # ── Agenix secrets (new; re-key with `agenix -r secrets/hermes-env.age` etc.) ──
  age.secrets = {
    hermes-env = {
      file = ../../secrets/hermes-env.age;
      owner = "kimb";
      group = "users";
      mode = "0640";
    };
    hermes-dashboard-session-token = {
      file = ../../secrets/hermes-dashboard-session-token.age;
      owner = "kimb";
      group = "users";
      mode = "0640";
    };
  };

  # Linger for kimb is already managed by home-manager's user declaration on
  # this host (kimb is a real login user) — the module's mkDefault linger
  # already fires for any declared user; nothing extra needed.

  # Nebula-layer firewall: allow the backend port from the mesh only (host
  # firewall stays closed; the nebula1 TUN traffic is filtered by the nebula
  # firewall rules). Q9: nebula-only exposure.
  kimb.nebula.extraInboundRules = [
    {
      port = cfg.backend.port;
      proto = "tcp";
      host = "any";
    }
  ];
}
