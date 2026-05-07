# Generate nebula certificates from YubiKey-encrypted CA
# This function generates a shell script that:
# 1. Decrypts the YubiKey-encrypted CA
# 2. Generates certificates for each host
# 3. Re-encrypts them with regular agenix (to host SSH keys)
{
  pkgs,
  lib,
  hostData,
  bootstrapKey,
}:
let
  yubikeyIdentity1 = builtins.toString ../secrets/identities/yubikey-1.pub;
  yubikeyIdentity2 = builtins.toString ../secrets/identities/yubikey-2.pub;
in
  pkgs.writeShellScript "generate-nebula-certs" ''
    set -e

    # Parse arguments
    DRY_RUN=false
    for arg in "$@"; do
      case "$arg" in
        --dry-run|-n)
          DRY_RUN=true
          ;;
        --help|-h)
          echo "Usage: nix run .#generate-nebula-certs [--dry-run]"
          echo ""
          echo "Options:"
          echo "  --dry-run, -n  Show what would be done without making changes"
          echo "  --help, -h     Show this help"
          exit 0
          ;;
      esac
    done

    cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || pwd)"

    echo "=== Nebula Certificate Generator ==="
    if $DRY_RUN; then
      echo "    [DRY RUN - no changes will be made]"
    fi
    echo ""
    echo "This script:"
    echo "  1. Decrypts the YubiKey-encrypted CA"
    echo "  2. Generates certificates for each host"
    echo "  3. Re-encrypts them with regular agenix (to host SSH keys)"
    echo ""

    # Show hosts that will be processed
    echo "Hosts from registry (with IP + publicKey):"
    ${lib.concatMapStringsSep "\n" (host: ''
        echo "  - ${host.name}: ${host.ip}/16, groups=[${lib.concatStringsSep "," host.groups}]"
      '')
      hostData}
    echo ""

    echo "Files that will be created/updated:"
    ${lib.concatMapStringsSep "\n" (host: ''
        echo "  - secrets/nebula-${host.name}-cert.age (encrypted to ${host.name} + bootstrap)"
        echo "  - secrets/nebula-${host.name}-key.age (encrypted to ${host.name} + bootstrap)"
      '')
      hostData}
    echo "  - secrets/nebula-ca.age (CA cert only, encrypted to all hosts)"
    echo ""

    if $DRY_RUN; then
      echo "=== Dry run complete ==="
      echo "Run without --dry-run to actually generate certificates."
      exit 0
    fi

    echo "Requirements: YubiKey with age identity must be plugged in"
    echo ""

    # Check for required tools
    command -v ${pkgs.age}/bin/age >/dev/null || { echo "Error: age not found"; exit 1; }
    command -v ${pkgs.nebula}/bin/nebula-cert >/dev/null || { echo "Error: nebula-cert not found"; exit 1; }

    # Create temp directory for working files
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    # Decrypt CA from YubiKey-encrypted file
    echo "Decrypting CA (touch YubiKey if prompted)..."
    CA_FILE="secrets/nebula-ca-master.age"
    if [ ! -f "$CA_FILE" ]; then
      echo "Error: $CA_FILE not found"
      echo "Make sure you've encrypted the CA with YubiKeys first"
      exit 1
    fi

    # age-plugin-yubikey must be in PATH for age to find it
    export PATH="${pkgs.age-plugin-yubikey}/bin:$PATH"

    # Decrypt using YubiKey identity files (plugin needs explicit identity)
    ${pkgs.age}/bin/age -d \
      -i "${yubikeyIdentity1}" \
      -i "${yubikeyIdentity2}" \
      "$CA_FILE" > "$TMPDIR/ca-combined.pem" || {
      echo "Error: Failed to decrypt CA. Is your YubiKey plugged in?"
      echo "Make sure age-plugin-yubikey is available (enter nix develop first)"
      exit 1
    }

    # Split CA into key and cert
    ${pkgs.gnused}/bin/sed -n '1,/END NEBULA ED25519 PRIVATE KEY/p' "$TMPDIR/ca-combined.pem" > "$TMPDIR/ca.key"
    ${pkgs.gnused}/bin/sed -n '/BEGIN NEBULA CERTIFICATE/,/END NEBULA CERTIFICATE/p' "$TMPDIR/ca-combined.pem" > "$TMPDIR/ca.crt"

    echo "CA decrypted successfully!"
    echo ""

    # Bootstrap key for re-encryption
    BOOTSTRAP_KEY="${bootstrapKey}"

    # Generate certs for each host
    ${lib.concatMapStringsSep "\n" (host: ''
        echo "Generating certificate for ${host.name}..."
        HOST_NAME="${host.name}"
        HOST_IP="${host.ip}"
        HOST_GROUPS="${lib.concatStringsSep "," host.groups}"
        HOST_PUBKEY="${host.publicKey}"

        # Generate cert and key
        ${pkgs.nebula}/bin/nebula-cert sign \
          -ca-crt "$TMPDIR/ca.crt" \
          -ca-key "$TMPDIR/ca.key" \
          -name "$HOST_NAME" \
          -ip "$HOST_IP/16" \
          -groups "$HOST_GROUPS" \
          -out-crt "$TMPDIR/$HOST_NAME.crt" \
          -out-key "$TMPDIR/$HOST_NAME.key"

        # Re-encrypt cert with agenix (to host key + bootstrap)
        ${pkgs.age}/bin/age -r "$HOST_PUBKEY" -r "$BOOTSTRAP_KEY" \
          -o "secrets/nebula-$HOST_NAME-cert.age" \
          "$TMPDIR/$HOST_NAME.crt"

        # Re-encrypt key with agenix (to host key + bootstrap)
        ${pkgs.age}/bin/age -r "$HOST_PUBKEY" -r "$BOOTSTRAP_KEY" \
          -o "secrets/nebula-$HOST_NAME-key.age" \
          "$TMPDIR/$HOST_NAME.key"

        echo "  ✓ secrets/nebula-$HOST_NAME-cert.age"
        echo "  ✓ secrets/nebula-$HOST_NAME-key.age"
        echo ""
      '')
      hostData}

    # Update the shared CA cert (public part only, for all hosts)
    echo "Updating shared CA certificate..."
    ${pkgs.age}/bin/age \
      ${lib.concatMapStringsSep " " (host: "-r \"${host.publicKey}\"") hostData} \
      -r "$BOOTSTRAP_KEY" \
      -o "secrets/nebula-ca.age" \
      "$TMPDIR/ca.crt"
    echo "  ✓ secrets/nebula-ca.age"
    echo ""

    echo "=== Done! ==="
    echo ""
    echo "Generated certificates are encrypted with regular agenix."
    echo "They can be decrypted by each host's SSH key."
    echo ""
    echo "Next steps:"
    echo "  1. Review the changes: jj diff"
    echo "  2. Commit: jj describe -m 'chore: regenerate nebula certificates'"
    echo "  3. Deploy: nix develop -c colmena apply"
  ''
