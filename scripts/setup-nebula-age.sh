#!/usr/bin/env bash
# Script to set up age encryption for Nebula certificates
# This creates encrypted secrets that can be safely stored in git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYS_DIR="$FLAKE_DIR/../flake_keys/nebula"
SECRETS_DIR="$FLAKE_DIR/secrets"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Setting up age encryption for Nebula certificates...${NC}"

# Check if age is available
if ! command -v age &> /dev/null; then
    echo -e "${RED}Error: age is not installed${NC}"
    echo "Install with: nix profile install nixpkgs#age"
    exit 1
fi

# Check if rage is available (better for key generation)
if ! command -v rage &> /dev/null; then
    echo -e "${YELLOW}Warning: rage not found, using age for key generation${NC}"
    KEY_GEN="age-keygen"
else
    KEY_GEN="rage-keygen"
fi

# Create secrets directory
mkdir -p "$SECRETS_DIR"

# Generate age key if it doesn't exist
AGE_KEY_FILE="$SECRETS_DIR/age-key.txt"
if [[ ! -f "$AGE_KEY_FILE" ]]; then
    echo -e "${YELLOW}Generating age key...${NC}"
    $KEY_GEN -o "$AGE_KEY_FILE"
    echo -e "${GREEN}Age key generated at $AGE_KEY_FILE${NC}"
    echo -e "${RED}IMPORTANT: Back up this key file securely!${NC}"
fi

# Extract public key
PUBLIC_KEY=$(grep -o 'age1[a-z0-9]*' "$AGE_KEY_FILE")
echo -e "${GREEN}Public key: $PUBLIC_KEY${NC}"

# Function to encrypt a file
encrypt_file() {
    local src="$1"
    local dst="$2"
    
    if [[ -f "$src" ]]; then
        echo "Encrypting $(basename "$src")..."
        age -r "$PUBLIC_KEY" -o "$dst" "$src"
    else
        echo -e "${RED}Warning: $src not found${NC}"
    fi
}

# Encrypt all certificates
echo -e "${YELLOW}Encrypting Nebula certificates...${NC}"

# CA certificate (shared by all)
encrypt_file "$KEYS_DIR/ca.crt" "$SECRETS_DIR/ca.crt.age"

# Individual machine certificates
for machine in historian marshmallow bartleby lighthouse; do
    echo "Processing $machine certificates..."
    encrypt_file "$KEYS_DIR/${machine}.crt" "$SECRETS_DIR/${machine}.crt.age"
    encrypt_file "$KEYS_DIR/${machine}.key" "$SECRETS_DIR/${machine}.key.age"
done

echo -e "${GREEN}Encryption complete!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Add the age key to your machines' configurations"
echo "2. Update your nebula configurations to use age secrets"
echo "3. The encrypted files in $SECRETS_DIR can be safely committed to git"
echo ""
echo -e "${RED}Remember to securely store the age key: $AGE_KEY_FILE${NC}"