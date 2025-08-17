#!/usr/bin/env bash
# Setup agenix for Nebula certificates using SSH host keys

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Setting up agenix for Nebula certificates...${NC}"

# Check if agenix is installed
if ! command -v agenix &> /dev/null; then
    echo -e "${YELLOW}Installing agenix...${NC}"
    nix profile install github:ryantm/agenix
fi

# Function to get SSH host key over Tailscale
get_host_key() {
    local host=$1
    echo -e "${YELLOW}Getting SSH host key from $host...${NC}"
    
    # Try to get the host key
    ssh-keyscan -t ed25519 "$host" 2>/dev/null | grep "ssh-ed25519" | cut -d' ' -f2-
}

# Collect host keys
echo -e "${GREEN}Collecting SSH host keys...${NC}"

# Create a temporary file for the keys
KEYS_FILE=$(mktemp)

echo "Collecting keys from your machines..."
echo "Make sure they're accessible via Tailscale!"
echo ""

for host in historian marshmallow bartleby rich-evans; do
    KEY=$(get_host_key "$host")
    if [[ -n "$KEY" ]]; then
        echo -e "${GREEN}✓${NC} Got key from $host"
        echo "$host = \"$KEY\";" >> "$KEYS_FILE"
    else
        echo -e "${RED}✗${NC} Failed to get key from $host"
    fi
done

echo ""
echo -e "${YELLOW}Update secrets/secrets.nix with these keys:${NC}"
cat "$KEYS_FILE"
rm "$KEYS_FILE"

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Update secrets/secrets.nix with the actual SSH host keys"
echo "2. Run: cd secrets && agenix -e nebula-ca.age"
echo "3. Paste the CA certificate content"
echo "4. Repeat for each machine's certificate and key"
echo ""
echo -e "${YELLOW}Example to encrypt a certificate:${NC}"
echo "  cd secrets"
echo "  agenix -e nebula-historian-cert.age"
echo "  # Paste content from ../flake_keys/nebula/historian.crt"