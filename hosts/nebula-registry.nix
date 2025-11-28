# Authoritative Host Registry
# Single source of truth for all host configuration
# All other files should reference this for IPs, SSH keys, roles, and groups
let
  # Network infrastructure (not hosts)
  networks = {
    nebula = {
      subnet = "10.100.0.0/16";
      lighthouse = {
        ip = "10.100.0.1";
        external = "35.222.40.201:4242";
      };
    };
    lan = {
      subnet = "192.168.69.0/24";
      gateway = "192.168.69.1";
      dhcp = {
        start = "192.168.69.100";
        end = "192.168.69.199";
      };
    };
    containers = {
      subnet = "192.168.100.0/24";
      bridge = "192.168.100.1";
      hosts = {
        reverse-proxy = "192.168.100.2";
        blog-service = "192.168.100.3";
        authelia = "192.168.100.4";
      };
    };
    tailscale.subnet = "100.64.0.0/10";
  };

  # All managed hosts with complete configuration
  hosts = {
    lighthouse = {
      ip = "10.100.0.1";
      external = "35.222.40.201:4242";
      isLighthouse = true;
      role = "lighthouse";
      groups = ["lighthouse"];
      publicKey = null; # External Google Cloud instance
    };

    historian = {
      ip = "10.100.0.10";
      role = "desktop";
      groups = ["desktops" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBXpuMSA1RXsYs6cEhvNqzhWpbIe2NB0ya1MUte87SD+";
    };

    total-eclipse = {
      ip = "10.100.0.6";
      role = "desktop";
      groups = ["desktops" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII25uGB19xLNzpzOFKUHp93EtNPxHXgeKotRDsdqdWa7";
    };

    marshmallow = {
      ip = "10.100.0.4";
      role = "laptop";
      groups = ["laptops" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILlKSgkr7eXGq9Lcg/5TfH9eudHLEP1q4zAvA8zhq9wh";
    };

    bartleby = {
      ip = "10.100.0.3";
      role = "laptop";
      groups = ["laptops" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGCZ/lfNz+FcRNwbRMeT658YOH0YdCgLRBn/bcegj7pi";
    };

    maitred = {
      ip = "10.100.0.50";
      lanIp = "192.168.69.1";
      role = "router";
      groups = ["routers" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXJ4JeYtJiV8ltScewAu+N8KYLy+muo+mP07XznOzjX";
    };

    rich-evans = {
      ip = "10.100.0.40";
      role = "server";
      groups = ["servers" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOCXEs7zN0NNdWyZ9MJ4pI0R8RAPH6EFj3E2Qp2Xzc1k";
    };

    arbus = {
      ip = "10.100.0.20";
      role = "camera";
      groups = ["cameras" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcAHg30CQV01JYsRlyhNbh0Noyo1iPnde9nqDtV5SJY";
    };
  };

  # Helper: filter hosts by role
  byRole = role: builtins.filter (h: h.role == role) (builtins.attrValues hosts);

  # Helper: get all NixOS hosts (exclude lighthouse)
  nixosHosts = builtins.removeAttrs hosts ["lighthouse"];

  # Helper: extract public keys from hosts with non-null keys
  getPublicKeys = hostSet:
    builtins.listToAttrs (
      builtins.filter (x: x.value != null)
      (map (name: {
          inherit name;
          value = hostSet.${name}.publicKey;
        })
        (builtins.attrNames hostSet))
    );
in {
  # Network configuration
  network = networks.nebula;
  inherit networks;

  # All nodes (for nebula config, colmena, etc.)
  nodes = hosts;

  # Convenience accessors
  inherit nixosHosts;
  desktops = builtins.filter (n: hosts.${n}.role == "desktop") (builtins.attrNames hosts);
  laptops = builtins.filter (n: hosts.${n}.role == "laptop") (builtins.attrNames hosts);
  servers = builtins.filter (n: hosts.${n}.role == "server") (builtins.attrNames hosts);

  # SSH host keys (for agenix)
  hostKeys = getPublicKeys nixosHosts;

  # Bootstrap key for agenix re-encryption (cheesecake user key)
  bootstrap = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQgFzMg37QTeFE2ybQRHfVEQwW/Wz7lK6jPPmctFd/U";
}
