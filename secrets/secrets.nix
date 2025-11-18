# Agenix secrets configuration
# This file defines which systems can decrypt which secrets
let
  # Import node registry for centralized management
  registry = import ../hosts/nebula-registry.nix;

  # Extract public keys from registry (filter out nodes without keys)
  nodesWithKeys =
    builtins.filter (node: node.publicKey != null)
    (builtins.attrValues registry.nodes);
  allSystems = map (node: node.publicKey) nodesWithKeys;

  # Temporary user key for bootstrap
  userBootstrapKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQgFzMg37QTeFE2ybQRHfVEQwW/Wz7lK6jPPmctFd/U";

  # Temporary: Only working machines (skip laptops for now)
  workingMachines = [
    registry.nodes.historian.publicKey
    registry.nodes.maitred.publicKey
    registry.nodes.rich-evans.publicKey
    registry.nodes.total-eclipse.publicKey
    registry.nodes.marshmallow.publicKey
    userBootstrapKey # Added temporarily for re-encryption
  ];
in
  {
    # Shared CA certificate - working systems only (temporary)
    "nebula-ca.age".publicKeys = workingMachines;

    # Cloudflare API token - only maitred needs this
    "cloudflare-api-token.age".publicKeys = [registry.nodes.maitred.publicKey];

    # Authelia secrets - maitred and historian (for initial setup)
    "authelia-jwt-secret.age".publicKeys = [registry.nodes.maitred.publicKey registry.nodes.historian.publicKey];
    "authelia-session-secret.age".publicKeys = [registry.nodes.maitred.publicKey registry.nodes.historian.publicKey];
    "authelia-storage-key.age".publicKeys = [registry.nodes.maitred.publicKey registry.nodes.historian.publicKey];
    "authelia-users.age".publicKeys = [registry.nodes.maitred.publicKey registry.nodes.historian.publicKey];
    "authelia-smtp-password.age".publicKeys = [registry.nodes.maitred.publicKey registry.nodes.historian.publicKey];

    # Individual certificates - only the specific system can decrypt
    # Generated dynamically from registry
  }
  // (
    let
      # Create cert/key entries only for working nodes (temporary)
      workingNodes = {
        inherit (registry.nodes) historian maitred rich-evans total-eclipse marshmallow;
      };
      createNodeSecrets = nodeName: node:
        if node.publicKey != null
        then {
          "nebula-${nodeName}-cert.age".publicKeys = [node.publicKey userBootstrapKey];
          "nebula-${nodeName}-key.age".publicKeys = [node.publicKey userBootstrapKey];
        }
        else {};
    in
      builtins.foldl' (acc: entry: acc // entry) {}
      (builtins.attrValues (builtins.mapAttrs createNodeSecrets workingNodes))
  )
