#!/usr/bin/env bash
# Quick script to encrypt all Nebula certificates with agenix

set -euo pipefail

cd secrets

# Install agenix if needed
if ! command -v agenix &> /dev/null; then
    echo "Installing agenix..."
    nix profile install github:ryantm/agenix
fi

echo "Encrypting Nebula certificates..."

# CA cert (everyone gets this)
agenix -e nebula-ca.age < ../../flake_keys/nebula/ca.crt

# Each machine's certs
for host in historian marshmallow bartleby rich-evans total-eclipse; do
    echo "Encrypting $host certificates..."
    agenix -e nebula-${host}-cert.age < ../../flake_keys/nebula/${host}.crt
    agenix -e nebula-${host}-key.age < ../../flake_keys/nebula/${host}.key
done

echo "Done! All certificates encrypted."