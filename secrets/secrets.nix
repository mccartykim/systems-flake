# Agenix secrets configuration
# This file defines which systems can decrypt which secrets
let
  # Import centralized SSH keys registry
  sshKeys = import ../hosts/ssh-keys.nix;
  host = sshKeys.host;
  bootstrap = sshKeys.bootstrap;

  # All working machines that can decrypt shared secrets
  workingMachines = [
    host.historian
    host.maitred
    host.rich-evans
    host.total-eclipse
    host.marshmallow
    host.arbus
    host.bartleby
    bootstrap # For re-encryption from workstation
  ];

  # Helper to create node cert/key secrets
  createNodeSecrets = name: key: {
    "nebula-${name}-cert.age".publicKeys = [key bootstrap];
    "nebula-${name}-key.age".publicKeys = [key bootstrap];
  };
in
  {
    # Shared CA certificate - all working systems
    "nebula-ca.age".publicKeys = workingMachines;

    # Cloudflare API token - only maitred needs this
    "cloudflare-api-token.age".publicKeys = [host.maitred];

    # Authelia secrets - maitred and historian
    "authelia-jwt-secret.age".publicKeys = [host.maitred host.historian];
    "authelia-session-secret.age".publicKeys = [host.maitred host.historian];
    "authelia-storage-key.age".publicKeys = [host.maitred host.historian];
    "authelia-users.age".publicKeys = [host.maitred host.historian];
    "authelia-smtp-password.age".publicKeys = [host.maitred host.historian];
  }
  # Individual nebula certificates - each node can only decrypt its own
  // createNodeSecrets "historian" host.historian
  // createNodeSecrets "maitred" host.maitred
  // createNodeSecrets "rich-evans" host.rich-evans
  // createNodeSecrets "total-eclipse" host.total-eclipse
  // createNodeSecrets "marshmallow" host.marshmallow
  // createNodeSecrets "arbus" host.arbus
  // createNodeSecrets "bartleby" host.bartleby
