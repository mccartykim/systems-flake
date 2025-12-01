# Agenix-rekey common configuration for all hosts
# This module sets up YubiKey-based secret management
{
  config,
  lib,
  inputs,
  outputs,
  ...
}: let
  hostName = config.networking.hostName;
  registry = import (outputs + "/hosts/nebula-registry.nix");
  # Get host public key from registry, or null if not in registry
  registryPubkey = registry.nodes.${hostName}.publicKey or null;
in {
  imports = [
    inputs.agenix.nixosModules.default
    inputs.agenix-rekey.nixosModules.default
  ];

  age.rekey = {
    # Use local storage mode - rekeyed secrets are committed to the repo
    storageMode = "local";
    localStorageDir = outputs + "/secrets/rekeyed/${hostName}";

    # YubiKey master identities - any single key can decrypt master secrets
    # Using .pub extension since the private parts are on the YubiKeys
    masterIdentities = [
      (outputs + "/secrets/identities/yubikey-1.pub")
      (outputs + "/secrets/identities/yubikey-2.pub")
    ];

    # Host public key from registry for encrypting rekeyed secrets
    # Falls back to reading from filesystem if host not in registry
    hostPubkey =
      if registryPubkey != null
      then registryPubkey
      else "/etc/ssh/ssh_host_ed25519_key.pub";
  };

  # Ensure agenix can find the SSH host key
  age.identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];
}
