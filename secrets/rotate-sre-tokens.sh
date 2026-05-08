#!/usr/bin/env bash
# Rotate SRE agent secrets (Discord bot token + GitHub PAT)
# Usage: ./rotate-sre-tokens.sh
# After running: jj describe -m "chore: rotate SRE agent tokens"
#                jj bookmark set main -r @ && jj git push
#                nix develop -c colmena apply --on rich-evans

set -euo pipefail
cd "$(dirname "$0")"

BOOTSTRAP_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQgFzMg37QTeFE2ybQRHfVEQwW/Wz7lK6jPPmctFd/U"
RICH_EVANS_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOCXEs7zN0NNdWyZ9MJ4pI0R8RAPH6EFj3E2Qp2Xzc1k"

echo "=== SRE Agent Token Rotation ==="
echo ""
echo "Enter new Discord bot token:"
read -r DISCORD_TOKEN
echo "Enter new GitHub PAT (must have repo:read/write on mccartykim/homelab-incidents):"
read -r GH_TOKEN

echo -n "$DISCORD_TOKEN" | age -r "$RICH_EVANS_KEY" -r "$BOOTSTRAP_KEY" -o discord-sre-token.age
echo "Encrypted discord-sre-token.age"

echo -n "$GH_TOKEN" | age -r "$RICH_EVANS_KEY" -r "$BOOTSTRAP_KEY" -o gh-sre-token.age
echo "Encrypted gh-sre-token.age"

echo ""
echo "Done. Commit and deploy with:"
echo "  jj describe -m 'chore: rotate SRE agent tokens'"
echo "  jj bookmark set main -r @ && jj git push"
echo "  nix develop -c colmena apply --on rich-evans"