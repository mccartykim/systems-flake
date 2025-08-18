# Nebula network node registry
# Single source of truth for all Nebula network nodes
{
  # Nebula network configuration
  network = {
    subnet = "10.100.0.0/16";
    lighthouse = {
      host = "35.222.40.201";
      port = 4242;
    };
  };

  # All nodes in the Nebula mesh
  nodes = {
    lighthouse = {
      ip = "10.100.0.1";
      external = "35.222.40.201:4242";
      isLighthouse = true;
      publicKey = null;  # Google Cloud instance, not NixOS managed
    };
    
    rich-evans = {
      ip = "10.100.0.40";
      isLighthouse = false;
      role = "server";  # Home server for DNS, print, media
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOCXEs7zN0NNdWyZ9MJ4pI0R8RAPH6EFj3E2Qp2Xzc1k";
    };
    
    historian = {
      ip = "10.100.0.10";
      isLighthouse = false;
      role = "desktop";  # AMD gaming/AI workstation
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBXpuMSA1RXsYs6cEhvNqzhWpbIe2NB0ya1MUte87SD+";
    };
    
    marshmallow = {
      ip = "10.100.0.4";
      isLighthouse = false;
      role = "laptop";  # ThinkPad T490
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILlKSgkr7eXGq9Lcg/5TfH9eudHLEP1q4zAvA8zhq9wh";
    };
    
    bartleby = {
      ip = "10.100.0.3";
      isLighthouse = false;
      role = "laptop";  # ThinkPad 131e netbook
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGCZ/lfNz+FcRNwbRMeT658YOH0YdCgLRBn/bcegj7pi";
    };
    
    total-eclipse = {
      ip = "10.100.0.6";
      isLighthouse = false;
      role = "desktop";  # Gaming desktop with NVIDIA
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII25uGB19xLNzpzOFKUHp93EtNPxHXgeKotRDsdqdWa7";
    };
    
    maitred = {
      ip = "10.100.0.50";
      isLighthouse = false;
      role = "router";  # Datto 1000 router/firewall
      publicKey = null;  # Will be filled after installation
    };
    
    # To add a new device:
    # 1. Add entry here with next available IP
    # 2. Add nixosConfiguration in flake.nix
    # 3. Run scripts/collect-age-keys.sh to get SSH key
    # 4. Update publicKey field above
    # 5. Build and deploy!
  };
}