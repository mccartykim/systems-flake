# Agenix-rekey configuration for YubiKey-based secret management
# The actual age.rekey.* options are set in NixOS configurations
# This module just documents the YubiKey recipients for reference
{self, ...}: {
  # YubiKey recipients for encrypting secrets:
  # - age1yubikey1q0qggwpjpkke4vetqyq0yun9k3qrxc0p4nrvmyxyjar4f9ryceczgpe3gjp (serial 27414451)
  # - age1yubikey1qd2t6jv9nhx5ndtlqm7dtzrkfawgd378nfpnju0chlzqjqq8lqf970rl5de (serial 30479043)
  #
  # Identity files are stored in secrets/identities/
  # Master CA is stored in secrets/nebula-ca-master.age
}
