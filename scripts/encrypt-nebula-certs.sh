#!/usr/bin/env bash
# Encrypt Nebula certificates for all machines using collected age keys

set -euo pipefail

KEYS_DIR="../flake_keys/nebula"
SECRETS_DIR="secrets"
RECIPIENTS_FILE="secrets/.age-recipients"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Check recipients file exists
if [[ ! -f "$RECIPIENTS_FILE" ]]; then
    echo -e "${RED}Error: Run ./scripts/collect-age-keys.sh first${NC}"
    exit 1
fi

echo "Encrypting Nebula certificates..."

# Encrypt CA cert for ALL machines
echo "Encrypting ca.crt for all machines..."
age -R "$RECIPIENTS_FILE" -o "$SECRETS_DIR/ca.crt.age" "$KEYS_DIR/ca.crt"

# Encrypt individual certs - each machine gets only its own
for machine in historian marshmallow bartleby rich-evans; do
    echo "Processing $machine..."
    
    # Extract just this machine's age key from recipients file
    key=$(grep -A1 "# $machine" "$RECIPIENTS_FILE" | tail -n1 | grep "^age1" || true)
    
    if [[ -z "$key" ]]; then
        echo -e "${RED}  ✗ No age key found for $machine (skipping)${NC}"
        continue
    fi
    
    if [[ -f "$KEYS_DIR/${machine}.crt" ]]; then
        age -r "$key" -o "$SECRETS_DIR/${machine}.crt.age" "$KEYS_DIR/${machine}.crt"
        age -r "$key" -o "$SECRETS_DIR/${machine}.key.age" "$KEYS_DIR/${machine}.key"
        echo -e "${GREEN}  ✓ Encrypted certs for $machine${NC}"
    else
        echo -e "${RED}  ✗ No certs found for $machine${NC}"
    fi
done

echo -e "${GREEN}Done! Encrypted certificates are in $SECRETS_DIR/${NC}"
echo "These .age files are safe to commit to git"