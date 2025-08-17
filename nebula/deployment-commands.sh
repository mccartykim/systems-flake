#!/bin/bash
# Copy these commands to deploy Nebula lighthouse to your Google Cloud instance

# 1. Copy all certificate files
echo "Copying certificates..."
scp ../flake_keys/nebula/ca.crt mccarty_tim@35.222.40.201:~/
scp ../flake_keys/nebula/lighthouse.crt mccarty_tim@35.222.40.201:~/
scp ../flake_keys/nebula/lighthouse.key mccarty_tim@35.222.40.201:~/

# 2. Copy configuration and service files
echo "Copying configuration files..."
scp lighthouse-config.yml mccarty_tim@35.222.40.201:~/
scp nebula-lighthouse.service mccarty_tim@35.222.40.201:~/
scp deploy-lighthouse.sh mccarty_tim@35.222.40.201:~/

# 3. SSH in and run setup
echo "Connect via SSH and run setup:"
echo "ssh mccarty_tim@35.222.40.201"
echo "chmod +x deploy-lighthouse.sh"
echo "./deploy-lighthouse.sh"

# 4. Manual steps to run on the server:
echo ""
echo "After running deploy-lighthouse.sh, execute these commands on the server:"
echo "sudo mv ca.crt lighthouse.crt lighthouse.key /etc/nebula/"
echo "sudo mv lighthouse-config.yml /etc/nebula/lighthouse.yml"
echo "sudo mv nebula-lighthouse.service /etc/systemd/system/"
echo "sudo chmod 600 /etc/nebula/*.key"
echo "sudo chmod 644 /etc/nebula/*.crt /etc/nebula/*.yml"
echo "sudo systemctl daemon-reload"
echo "sudo systemctl enable nebula-lighthouse"
echo "sudo systemctl start nebula-lighthouse"
echo "sudo systemctl status nebula-lighthouse"