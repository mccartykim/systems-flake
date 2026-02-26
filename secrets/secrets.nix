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

    # ===== BUILDNET (hot CA for untrusted builders like Claude Code) =====
    # Buildnet CA (maitred manages, historian + oracle need ca.crt for verification)
    "buildnet-ca-cert.age".publicKeys = [hostKeys.maitred hostKeys.historian oracleKey bootstrap];
    "buildnet-ca-key.age".publicKeys = [hostKeys.maitred bootstrap];

    # Buildnet lighthouse certs (maitred primary, oracle secondary)
    "buildnet-lighthouse-cert.age".publicKeys = [hostKeys.maitred bootstrap];
    "buildnet-lighthouse-key.age".publicKeys = [hostKeys.maitred bootstrap];
    "buildnet-oracle-cert.age".publicKeys = [oracleKey bootstrap];
    "buildnet-oracle-key.age".publicKeys = [oracleKey bootstrap];

    # Buildnet historian cert (for dual-homing)
    "buildnet-historian-cert.age".publicKeys = [hostKeys.historian bootstrap];
    "buildnet-historian-key.age".publicKeys = [hostKeys.historian bootstrap];

    # ===== CONTAINERNET (hot CA for container service mesh) =====
    # Containernet CA (maitred + oracle need it)
    "containernet-ca-cert.age".publicKeys = [hostKeys.maitred oracleKey bootstrap];
    "containernet-ca-key.age".publicKeys = [hostKeys.maitred bootstrap];

    # Containernet lighthouse certs (maitred primary, oracle secondary)
    "containernet-lighthouse-cert.age".publicKeys = [hostKeys.maitred bootstrap];
    "containernet-lighthouse-key.age".publicKeys = [hostKeys.maitred bootstrap];
    "containernet-oracle-cert.age".publicKeys = [oracleKey bootstrap];
    "containernet-oracle-key.age".publicKeys = [oracleKey bootstrap];

    # Containernet reverse-proxy cert (static IP 10.102.0.10 for Caddy bridge)
    "containernet-reverse-proxy-cert.age".publicKeys = [hostKeys.maitred bootstrap];
    "containernet-reverse-proxy-key.age".publicKeys = [hostKeys.maitred bootstrap];

    # ===== CERT SERVICE =====
    # API token for cert allocation service
    "cert-service-token.age".publicKeys = [hostKeys.maitred bootstrap];

    # ===== LIFE COACH AGENT =====
    # Home Assistant long-lived access token for presence sensor queries
    "ha-life-coach-token.age".publicKeys = [hostKeys.rich-evans hostKeys.historian hostKeys.marshmallow bootstrap];

    # ===== MEDIA PIPELINE (historian) =====
    # rclone config with put.io OAuth token
    "rclone-config.age".publicKeys = [hostKeys.historian bootstrap];
    # Anthropic API key for Claude Haiku media classifier fallback
    "anthropic-api-key.age".publicKeys = [hostKeys.historian bootstrap];

    # ===== RESTIC BACKUPS (Backblaze B2) =====
    # All hosts can decrypt for deduplication across syncthing-replicated data
    "restic-password.age".publicKeys = workingMachines;
    "restic-b2-env.age".publicKeys = workingMachines;
  }
  // allNebulaSecrets
