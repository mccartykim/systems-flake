#!/usr/bin/env bash
set -euo pipefail

# Nebula network setup script
# This creates a CA and certificates for all your devices

NEBULA_VERSION="v1.9.3"
CERT_DIR="./certs"
CONFIG_DIR="./configs"

# Network configuration
NETWORK_NAME="kimb-mesh"
NETWORK_CIDR="10.100.0.0/16"

# Device definitions
# Format: "name:ip:groups:is_lighthouse"
DEVICES=(
    # Lighthouse (Google Cloud)
    "google-lighthouse:10.100.0.1:lighthouse:true"
    
    # Laptops/Desktops
    "marshmallow:10.100.0.10:laptops,nixos:false"
    "bartleby:10.100.0.11:laptops,nixos:false"
    "total-eclipse:10.100.0.12:desktops,nixos:false"
    "historian:10.100.0.13:desktops,nixos:false"
    
    # Servers
    "rich-evans:10.100.0.20:servers,nixos:false"
    
    # Mobile/ARM devices
    "bonbon:10.100.0.30:mobile,nixos:false"
    
    # macOS devices
    "cronut:10.100.0.40:laptops,macos:false"
    "kmccarty-YM2K:10.100.0.41:laptops,macos,work:false"
)

# Download nebula-cert if not present
if [ ! -f "./nebula-cert" ]; then
    echo "Downloading nebula-cert..."
    case "$(uname -s)" in
        Linux)
            wget "https://github.com/slackhq/nebula/releases/download/${NEBULA_VERSION}/nebula-linux-amd64.tar.gz"
            tar -xzf nebula-linux-amd64.tar.gz nebula-cert
            rm nebula-linux-amd64.tar.gz
            ;;
        Darwin)
            wget "https://github.com/slackhq/nebula/releases/download/${NEBULA_VERSION}/nebula-darwin.zip"
            unzip -j nebula-darwin.zip nebula-cert
            rm nebula-darwin.zip
            ;;
        *)
            echo "Unsupported OS"
            exit 1
            ;;
    esac
    chmod +x nebula-cert
fi

# Create directories
mkdir -p "$CERT_DIR" "$CONFIG_DIR"

# Generate CA certificate
if [ ! -f "$CERT_DIR/ca.crt" ]; then
    echo "Generating Nebula CA certificate..."
    ./nebula-cert ca -name "$NETWORK_NAME" -out-crt "$CERT_DIR/ca.crt" -out-key "$CERT_DIR/ca.key"
else
    echo "CA certificate already exists, skipping..."
fi

# Generate device certificates
echo "Generating device certificates..."
for device in "${DEVICES[@]}"; do
    IFS=':' read -r name ip groups is_lighthouse <<< "$device"
    
    if [ ! -f "$CERT_DIR/${name}.crt" ]; then
        echo "Generating certificate for $name ($ip)..."
        ./nebula-cert sign \
            -ca-crt "$CERT_DIR/ca.crt" \
            -ca-key "$CERT_DIR/ca.key" \
            -name "$name" \
            -ip "$ip/32" \
            -groups "$groups" \
            -out-crt "$CERT_DIR/${name}.crt" \
            -out-key "$CERT_DIR/${name}.key"
    else
        echo "Certificate for $name already exists, skipping..."
    fi
done

# Generate configuration files
echo "Generating configuration files..."

# Lighthouse config template
cat > "$CONFIG_DIR/lighthouse-config.yml" << 'EOF'
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/google-lighthouse.crt
  key: /etc/nebula/google-lighthouse.key

static_host_map:
  # Lighthouse doesn't need static mappings

lighthouse:
  am_lighthouse: true
  interval: 60

listen:
  host: 0.0.0.0
  port: 4242

punchy:
  punch: true
  respond: true

relay:
  am_relay: true
  use_relays: false

tun:
  disabled: false
  dev: nebula1
  drop_local_broadcast: false
  drop_multicast: false
  tx_queue: 500
  mtu: 1300

logging:
  level: info
  format: text

firewall:
  conntrack:
    tcp_timeout: 12m
    udp_timeout: 3m
    default_timeout: 10m

  outbound:
    - port: any
      proto: any
      host: any

  inbound:
    # Allow all from the mesh
    - port: any
      proto: icmp
      host: any
      
    # SSH from anywhere in the mesh
    - port: 22
      proto: tcp
      groups:
        - laptops
        - desktops
        - servers
        - mobile
EOF

# Regular node config template
cat > "$CONFIG_DIR/node-config-template.yml" << 'EOF'
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/NODE_NAME.crt
  key: /etc/nebula/NODE_NAME.key

static_host_map:
  "10.100.0.1": ["LIGHTHOUSE_PUBLIC_IP:4242"]

lighthouse:
  am_lighthouse: false
  interval: 60
  hosts:
    - "10.100.0.1"

listen:
  host: 0.0.0.0
  port: 0  # Random port

punchy:
  punch: true

relay:
  relays:
    - 10.100.0.1
  am_relay: false
  use_relays: true

tun:
  disabled: false
  dev: nebula1
  drop_local_broadcast: false
  drop_multicast: false
  tx_queue: 500
  mtu: 1300

logging:
  level: info
  format: text

firewall:
  conntrack:
    tcp_timeout: 12m
    udp_timeout: 3m
    default_timeout: 10m

  outbound:
    - port: any
      proto: any
      host: any

  inbound:
    # Allow all ICMP
    - port: any
      proto: icmp
      host: any
      
    # SSH from mesh
    - port: 22
      proto: tcp
      host: any
      
    # mDNS for local discovery
    - port: 5353
      proto: udp
      host: any
EOF

echo ""
echo "✅ Nebula network setup complete!"
echo ""
echo "📁 Certificates created in: $CERT_DIR/"
echo "📁 Config templates in: $CONFIG_DIR/"
echo ""
echo "🌐 Network topology:"
echo "  Network: $NETWORK_CIDR"
echo "  Lighthouse: google-lighthouse (10.100.0.1)"
echo ""
echo "📝 Next steps:"
echo "  1. Deploy lighthouse to Google Cloud with the certs"
echo "  2. Update node configs with lighthouse's public IP"
echo "  3. Distribute certificates to each device"
echo "  4. Add Nebula service configuration to each host"
echo ""
echo "💡 SSH between devices:"
echo "  ssh admin@10.100.0.10  # marshmallow"
echo "  ssh admin@10.100.0.20  # rich-evans"
echo "  etc..."