# Agenix secrets configuration
# Defines which systems can decrypt which secrets
let
  registry = import ../hosts/nebula-registry.nix;
  inherit (registry) hostKeys bootstrap;

  # Oracle key from registry (system-manager host, not in hostKeys)
  oracleKey = registry.nodes.oracle.publicKey;

  # Mochi key from registry (system-manager host, not in hostKeys)
  mochiKey = registry.nodes.mochi.publicKey;

  # All working machines that can decrypt shared secrets
  workingMachines = (builtins.attrValues hostKeys) ++ [bootstrap oracleKey mochiKey];

  # Helper to create node cert/key secrets for a host
  createNodeSecrets = name: {
    "nebula-${name}-cert.age".publicKeys = [hostKeys.${name} bootstrap];
    "nebula-${name}-key.age".publicKeys = [hostKeys.${name} bootstrap];
  };

  # Generate nebula secrets for all NixOS hosts
  allNebulaSecrets =
    builtins.foldl' (acc: name: acc // createNodeSecrets name) {}
    (builtins.attrNames hostKeys);
in
  {
    # Shared CA certificate - all working systems
    "nebula-ca.age".publicKeys = workingMachines;

    # Cloudflare API token - only maitred needs this
    "cloudflare-api-token.age".publicKeys = [hostKeys.maitred bootstrap];

    # Authelia secrets - maitred and historian
    "authelia-jwt-secret.age".publicKeys = [hostKeys.maitred hostKeys.historian bootstrap];
    "authelia-session-secret.age".publicKeys = [hostKeys.maitred hostKeys.historian bootstrap];
    "authelia-storage-key.age".publicKeys = [hostKeys.maitred hostKeys.historian bootstrap];
    "authelia-users.age".publicKeys = [hostKeys.maitred hostKeys.historian bootstrap];
    "authelia-smtp-password.age".publicKeys = [hostKeys.maitred hostKeys.historian bootstrap];
    # Oracle (system-manager host) nebula secrets
    "nebula-oracle-cert.age".publicKeys = [oracleKey bootstrap];
    "nebula-oracle-key.age".publicKeys = [oracleKey bootstrap];

    # Mochi (system-manager host) nebula secrets
    "nebula-mochi-cert.age".publicKeys = [mochiKey bootstrap];
    "nebula-mochi-key.age".publicKeys = [mochiKey bootstrap];

    # ===== LIFE COACH AGENT =====
    # Home Assistant long-lived access token for presence sensor queries
    "ha-life-coach-token.age".publicKeys = [hostKeys.rich-evans hostKeys.historian hostKeys.marshmallow bootstrap];
    # Matrix access token for life-coach chatbot (Tuwunel on rich-evans)
    "matrix-life-coach-token.age".publicKeys = [hostKeys.rich-evans bootstrap];
    # Discord bot token for life-coach chatbot
    "discord-life-coach-token.age".publicKeys = [hostKeys.rich-evans bootstrap];
    # Gemini API key for life-coach vision
    "gemini-life-coach-key.age".publicKeys = [hostKeys.rich-evans bootstrap];

    # ===== VACUUM ORGANISM =====
    # Discord bot token for vacuum_organism sidecar (separate Discord
    # application from life-coach; see lib/discord_bot.py fail-closed
    # allowlist semantics).
    "discord-vacuum-bot-token.age".publicKeys = [hostKeys.rich-evans bootstrap];

    # ===== EMAIL / MAIL =====
    # Mail account passwords for mbsync on rich-evans (pull-only sync)
    # Used by both email-digest and org-crm services
    "mail-zoho-password.age".publicKeys = [hostKeys.rich-evans bootstrap];
    "mail-gmail-password.age".publicKeys = [hostKeys.rich-evans bootstrap];
    "mail-fastmail-password.age".publicKeys = [hostKeys.rich-evans bootstrap];

    # ===== ORG-CRM =====
    # Discord bot token for CRM agent (separate from life-coach)
    # Uncomment after creating Discord application and encrypting token:
    "discord-org-crm-token.age".publicKeys = [hostKeys.rich-evans bootstrap];

    # ===== BUILDBOT-NIX CI =====
    # Master lives on rich-evans, worker on historian.
    # GitHub App private key PEM (rich-evans master uses this to authenticate to GitHub)
    "buildbot-github-app-key.age".publicKeys = [hostKeys.rich-evans bootstrap];
    # Webhook shared secret (entered in the GitHub App's webhook config)
    "buildbot-webhook-secret.age".publicKeys = [hostKeys.rich-evans bootstrap];
    # GitHub App OAuth client secret (used for user login to buildbot UI)
    "buildbot-oauth-secret.age".publicKeys = [hostKeys.rich-evans bootstrap];
    # workers.json: JSON array of {name, pass, cores} entries for the master
    "buildbot-workers.age".publicKeys = [hostKeys.rich-evans bootstrap];
    # Worker-side password file (same string as the "pass" field in workers.json)
    "buildbot-worker-password.age".publicKeys = [hostKeys.historian bootstrap];
    # Fine-grained PAT for fetching private flake inputs from
    # mccartykim/* (Contents: Read). File contents: a single line
    # `access-tokens = github.com=<the-pat>` — included verbatim into
    # nix.conf via `nix.extraOptions = "!include ..."` on historian.
    "buildbot-worker-github-token.age".publicKeys = [hostKeys.historian bootstrap];
    # Same PAT in .netrc format. Used by nix's `git+https://` fetcher:
    # nix shells out to `git`, which reads /root/.netrc to authenticate
    # the clone. (The `access-tokens` setting only covers the github:
    # and tarball fetchers, not git-protocol clones.) Decrypted directly
    # to /root/.netrc on historian — see hosts/historian/buildbot-worker.nix.
    "buildbot-worker-git-netrc.age".publicKeys = [hostKeys.historian bootstrap];

    # ===== MEDIA PIPELINE (historian) =====
    # rclone config with put.io OAuth token
    "rclone-config.age".publicKeys = [hostKeys.historian bootstrap];
    # ===== RESTIC BACKUPS (Backblaze B2) =====
    # All hosts can decrypt for deduplication across syncthing-replicated data
    "restic-password.age".publicKeys = workingMachines;
    "restic-b2-env.age".publicKeys = workingMachines;

    # ===== Z.AI API (claude-zai wrapper) =====
    # z.ai serves a Claude-compatible endpoint; consumed by the claude-zai
    # wrapper in home/modules/ai-tools.nix. Owner is kimb (interactive user).
    "zai-api-key.age".publicKeys = [hostKeys.marshmallow hostKeys.historian hostKeys.rich-evans bootstrap];
  }
  // allNebulaSecrets
