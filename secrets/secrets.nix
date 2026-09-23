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

  # Fleet-core recipient set (a3j.10): the two always-on boxes. Service
  # secrets keyed to fleetCore move between fleet-core hosts with NO re-key
  # ceremony — the recipient set is the unit, not the host. Bootstrap stays
  # appended per-secret below, so re-encryption from a bootstrap identity
  # remains possible no matter which fleet-core host a service lives on.
  fleetCore = [hostKeys.historian hostKeys.rich-evans];

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

    # Cloudflare API token - maitred consumer (DDNS), pre-keyed for
    # historian (a3j.10) ahead of the phase-5 maitred duty migration.
    # maitred keeps decryptability as a cold spare (retiring hosts stay in
    # the registry forever).
    "cloudflare-api-token.age".publicKeys = [hostKeys.maitred hostKeys.historian bootstrap];
    # Grafana secret key - maitred consumer (grafana), pre-keyed for
    # historian (a3j.10, phase-5 prometheus/grafana migration). Cold-spare
    # rule as above.
    "grafana-secret-key.age".publicKeys = [hostKeys.maitred hostKeys.historian bootstrap];

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
    # Matrix access token for life-coach chatbot (Tuwunel; a3j.10 pre-key
    # to fleet-core for the a3j.6 Tuwunel migration to historian)
    "matrix-life-coach-token.age".publicKeys = fleetCore ++ [bootstrap];
    # Discord bot token for life-coach chatbot (a3j.10 pre-key to
    # fleet-core; life-coach stack migrates in a3j.6/a3j.7)
    "discord-life-coach-token.age".publicKeys = fleetCore ++ [bootstrap];

    # ===== VACUUM ORGANISM =====
    # Discord bot token for vacuum_organism sidecar (separate Discord
    # application from life-coach; see lib/discord_bot.py fail-closed
    # allowlist semantics). a3j.10 pre-key to fleet-core ahead of the a3j.7
    # organisms domU (re-keys to the domU host key when it exists).
    "discord-vacuum-bot-token.age".publicKeys = fleetCore ++ [bootstrap];

    # ===== EMAIL / MAIL =====
    # Mail account passwords for mbsync (pull-only sync). Used by both
    # email-digest and org-crm services. a3j.10 pre-key to fleet-core ahead
    # of the a3j.6 email-digest/org-crm migration (Maildir rides the
    # seagate; the mu xapian index rebuilds on historian's NVMe).
    "mail-zoho-password.age".publicKeys = fleetCore ++ [bootstrap];
    "mail-gmail-password.age".publicKeys = fleetCore ++ [bootstrap];
    "mail-fastmail-password.age".publicKeys = fleetCore ++ [bootstrap];

    # ===== ORG-CRM =====
    # Discord bot token for CRM agent (separate from life-coach).
    # a3j.10 pre-key to fleet-core ahead of the a3j.6 org-crm migration.
    "discord-org-crm-token.age".publicKeys = fleetCore ++ [bootstrap];

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

    # ===== BRIDGE CREW — REMOVED 2026-09-23 =====
    # The 40k "bridge officer" roleplay stack (11 character agents +
    # org-bridge broker + vox-bridge / vox-organism transports + the
    # bridge-scribe authoring servitor + the Nebula-only forgejo) was removed
    # wholesale. The four officer-only .age files moved out of this tree to
    # ../crew_secrets (kept sealed, no longer referenced by any config):
    #   matrix-vox-bridge-token.age   @vox-bridge:kimb.dev Matrix token
    #   bridge-fleet-ssh-key.age      rich-evans daemon -> historian hop
    #   deploy-key-bridge-scribe.age  bridge-scribe GitHub deploy key
    #   forge-bot-token.age           forgejo application token
    # A dangling owner (e.g. "vox-organism") would break evaluation once the
    # officer service users are gone, so no stanzas remain. See
    # docs/lifecoach-handoff.md for the removal record.

    # ===== MEDIA PIPELINE (historian) =====
    # rclone config with put.io OAuth token
    "rclone-config.age".publicKeys = [hostKeys.historian hostKeys.rich-evans bootstrap];
    # Jellyfin API key for media-classifier library rescan trigger
    "jellyfin-api-key.age".publicKeys = [hostKeys.historian bootstrap];
    # ===== RESTIC BACKUPS (Backblaze B2) =====
    # All hosts can decrypt for deduplication across syncthing-replicated data
    "restic-password.age".publicKeys = workingMachines;
    "restic-b2-env.age".publicKeys = workingMachines;

    # ===== Z.AI API (claude-zai wrapper) =====
    # z.ai serves a Claude-compatible endpoint; consumed by the claude-zai
    # wrapper in home/modules/ai-tools.nix. Owner is kimb (interactive user).
    "zai-api-key.age".publicKeys = [hostKeys.marshmallow hostKeys.historian hostKeys.rich-evans hostKeys.cheesecake bootstrap];

    # ===== SRE AGENT =====
    # GitHub fine-grained PAT for filing issues in mccartykim/homelab-incidents
    # (Issues: read/write on that repo only). Decrypted on rich-evans.
    # a3j.10 audit: SRE stack is currently disabled on rich-evans — NOT
    # pre-keyed for historian; keep-or-drop decided at rich-evans retirement.
    "gh-sre-token.age".publicKeys = [hostKeys.rich-evans bootstrap];
    # Discord bot token for SRE alert notifications (#sre-alerts channel).
    # Separate bot application from life-coach/vacuum/org-crm.
    # a3j.10 audit: as above — SRE stack disabled, not pre-keyed for
    # historian; keep-or-drop at rich-evans retirement.
    "discord-sre-token.age".publicKeys = [hostKeys.rich-evans bootstrap];
    # Ollama Cloud API key for LLM inference on rich-evans.
    # Get key from https://ollama.com/settings/api-keys
    # NOTE (a3j.10, user decision 2026-09-08): ollama cloud auth is USERLAND
    # — `ollama signin` managed ad hoc per host over ssh, NOT agenix — so
    # historian is intentionally NOT a recipient; it re-provisions cloud
    # auth manually as a known one-time step on rebuild/new-host.
    "ollama-cloud-key.age".publicKeys = [hostKeys.rich-evans hostKeys.cheesecake hostKeys.marshmallow bootstrap];

    # ===== KNITWORK (rich-evans) =====
    # Moderation admin bearer token for the knitwork AppView's
    # POST/DELETE /admin/hidden de-index/restore path (Stage 4). The token value
    # itself is never in any repo/flake — only this encrypted file is. a3j.10
    # pre-key to fleet-core (decryptable on rich-evans + historian) ahead of
    # the a3j.5 knitwork migration; consumed through
    # services.knitwork.adminTokenFile -> KNIT_ADMIN_TOKEN_FILE. See
    # hosts/rich-evans/knitwork.nix.
    "knit-admin-token.age".publicKeys = fleetCore ++ [bootstrap];

    # Confidential OAuth client P-256 private key (multibase) for the knitwork
    # BFF's private_key_jwt client auth. The key value is never in any repo/flake
    # — only this encrypted file. a3j.10 pre-key to fleet-core (decryptable
    # on rich-evans + historian) ahead of the a3j.5 knitwork-BFF migration;
    # consumed through services.knitwork-bff.clientKeyFile -> KNIT_CLIENT_KEY. See
    # hosts/rich-evans/knitwork-bff.nix. Generated with the knitwork repo's
    # bff/cmd/genkey, then age-encrypted to rich-evans + bootstrap here.
    "knit-bff-client-key.age".publicKeys = fleetCore ++ [bootstrap];

    # ===== BORGES (rich-evans) =====
    # systemd EnvironmentFile for the borges ebook server: BORGES_ADMIN_PASS
    # (required), BORGES_APP_PASS_KEY (pepper for app-passwords/sessions — lives
    # outside the DB so a DB leak alone can't forge a session or brute-force a
    # PIN), BORGES_BASE_URL (https://borges.kimb.dev -> Secure session cookie).
    # The values are never in any repo/flake — only this encrypted file.
    # a3j.10 pre-key to fleet-core (decryptable on rich-evans + historian)
    # ahead of the a3j.5 borges migration; consumed through
    # services.borges.environmentFile -> systemd EnvironmentFile=. See
    # hosts/rich-evans/borges.nix.
    "borges-env.age".publicKeys = fleetCore ++ [bootstrap];
  }
  // allNebulaSecrets
