#!/usr/bin/env bash
# Collect age public keys from all machines for Nebula encryption

set -euo pipefail

# Servers (usually online)
SERVERS="rich-evans"
# Desktops (usually online)
DESKTOPS="historian"
# Laptops (might be offline)
LAPTOPS="marshmallow bartleby"
MACHINES="$SERVERS $DESKTOPS $LAPTOPS"
RECIPIENTS_FILE="secrets/.age-recipients"

echo "# Age recipients for Nebula - $(date)" > "$RECIPIENTS_FILE"
echo "# Generated from SSH host keys" >> "$RECIPIENTS_FILE"
echo "" >> "$RECIPIENTS_FILE"

for host in $MACHINES; do
    echo "Collecting age key from $host..."
    if ssh -t -o ConnectTimeout=5 "$host" "sudo ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null" >> "$RECIPIENTS_FILE" 2>/dev/null; then
        echo "# $host" >> "$RECIPIENTS_FILE"
        echo "✓ Got key from $host"
    else
        echo "✗ Failed to connect to $host (skipping)"
    fi
    echo "" >> "$RECIPIENTS_FILE"
done

echo "Recipients file created at $RECIPIENTS_FILE"
echo "Next: Run ./scripts/encrypt-nebula-certs.sh"