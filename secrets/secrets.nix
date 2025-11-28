# Agenix secrets configuration
# Defines which systems can decrypt which secrets
let
  registry = import ../hosts/nebula-registry.nix;
  inherit (registry) hostKeys bootstrap;

  # All working machines that can decrypt shared secrets
  workingMachines = (builtins.attrValues hostKeys) ++ [bootstrap];

  # Helper to create node cert/key secrets for a host
  createNodeSecrets = name: {
    "nebula-${name}-cert.age".publicKeys = [hostKeys.${name} bootstrap];
    "nebula-${name}-key.age".publicKeys = [hostKeys.${name} bootstrap];
  };

  # Generate nebula secrets for all NixOS hosts
  allNebulaSecrets = builtins.foldl' (acc: name: acc // createNodeSecrets name) {}
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
  }
  // allNebulaSecrets
