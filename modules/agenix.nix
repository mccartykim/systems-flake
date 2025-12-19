# Agenix common configuration for all hosts
# Secrets are generated via `nix run .#generate-nebula-certs` (requires YubiKey)
# and encrypted to host SSH keys for decryption at boot
{inputs, ...}: {
  imports = [
    inputs.agenix.nixosModules.default
  ];

  # Ensure agenix can find the SSH host key for decryption
  age.identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];
}
