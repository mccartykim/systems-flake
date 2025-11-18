# Authoritative Nebula Network Registry
# Single source of truth for all nebula network configuration
# All other files should reference this for IP addresses and SSH keys
let
  networkIPs = import ./network-ips.nix;
in {
  # Network configuration
  network = {
    subnet = networkIPs.nebula.subnet;
    lighthouse = {
      ip = networkIPs.nebula.lighthouse.ip;
      external = networkIPs.nebula.lighthouse.external;
    };
  };

  # All nebula nodes with their complete configuration
  nodes = {
    lighthouse = {
      ip = networkIPs.nebula.lighthouse.ip;
      external = networkIPs.nebula.lighthouse.external;
      isLighthouse = true;
      role = "lighthouse";
      groups = ["lighthouse"];
      # No SSH key - external Google Cloud instance
      publicKey = null;
    };

    rich-evans = {
      ip = networkIPs.nebula.hosts.rich-evans;
      isLighthouse = false;
      role = "server";
      groups = ["servers" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOCXEs7zN0NNdWyZ9MJ4pI0R8RAPH6EFj3E2Qp2Xzc1k";
    };

    maitred = {
      ip = networkIPs.nebula.hosts.maitred;
      isLighthouse = false;
      role = "router";
      groups = ["routers" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXJ4JeYtJiV8ltScewAu+N8KYLy+muo+mP07XznOzjX";
    };

    historian = {
      ip = networkIPs.nebula.hosts.historian;
      isLighthouse = false;
      role = "desktop";
      groups = ["desktops" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBXpuMSA1RXsYs6cEhvNqzhWpbIe2NB0ya1MUte87SD+";
    };

    total-eclipse = {
      ip = networkIPs.nebula.hosts.total-eclipse;
      isLighthouse = false;
      role = "desktop";
      groups = ["desktops" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII25uGB19xLNzpzOFKUHp93EtNPxHXgeKotRDsdqdWa7";
    };

    marshmallow = {
      ip = networkIPs.nebula.hosts.marshmallow;
      isLighthouse = false;
      role = "laptop";
      groups = ["laptops" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILlKSgkr7eXGq9Lcg/5TfH9eudHLEP1q4zAvA8zhq9wh";
    };

    bartleby = {
      ip = networkIPs.nebula.hosts.bartleby;
      isLighthouse = false;
      role = "laptop";
      groups = ["laptops" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGCZ/lfNz+FcRNwbRMeT658YOH0YdCgLRBn/bcegj7pi";
    };
  };
}
