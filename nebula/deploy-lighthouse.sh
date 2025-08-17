#!/bin/bash
# Nebula Lighthouse Deployment Script for Debian/Ubuntu
# Run this on your Google Cloud Debian instance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up Nebula Lighthouse on Debian...${NC}"

# 1. Download and install Nebula
echo -e "${YELLOW}Installing Nebula...${NC}"
NEBULA_VERSION="v1.9.5"
wget -q "https://github.com/slackhq/nebula/releases/download/${NEBULA_VERSION}/nebula-linux-amd64.tar.gz"
tar -xzf nebula-linux-amd64.tar.gz
sudo mv nebula /usr/local/bin/
sudo mv nebula-cert /usr/local/bin/
rm nebula-linux-amd64.tar.gz
sudo chmod +x /usr/local/bin/nebula
sudo chmod +x /usr/local/bin/nebula-cert

# 2. Create nebula directory
echo -e "${YELLOW}Creating Nebula configuration directory...${NC}"
sudo mkdir -p /etc/nebula

# 3. Set up certificates (you'll need to copy these manually)
echo -e "${YELLOW}Certificate setup required:${NC}"
echo "You need to copy these files to the server:"
echo "  ca.crt -> /etc/nebula/ca.crt"
echo "  lighthouse.crt -> /etc/nebula/lighthouse.crt" 
echo "  lighthouse.key -> /etc/nebula/lighthouse.key"
echo "  lighthouse-config.yml -> /etc/nebula/lighthouse.yml"

# 4. Set up firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
sudo ufw allow 4242/udp comment 'Nebula lighthouse'
sudo ufw allow 22/tcp comment 'SSH'

# 5. Enable IP forwarding (for relay functionality)
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 6. Install and enable systemd service
echo -e "${YELLOW}Setting up systemd service...${NC}"
# Service file should be copied to /etc/systemd/system/nebula-lighthouse.service

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy certificate files to /etc/nebula/"
echo "2. Copy nebula-lighthouse.service to /etc/systemd/system/"
echo "3. Run: sudo systemctl daemon-reload"
echo "4. Run: sudo systemctl enable nebula-lighthouse"
echo "5. Run: sudo systemctl start nebula-lighthouse"
echo "6. Check status: sudo systemctl status nebula-lighthouse"
