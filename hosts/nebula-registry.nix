# Authoritative Host Registry
# Single source of truth for all host configuration
# All other files should reference this for IPs, SSH keys, roles, and groups
#
# Naming conventions:
#   - Portables: sweets (marshmallow, cheesecake, cronut) *bartleby predates this
#   - Desktops/servers: references/puns (historian, total-eclipse, rich-evans)
#   - Infrastructure: roles (maitred, lighthouse)
let
  # Network infrastructure (not hosts)
  networks = {
    nebula = {
      subnet = "10.100.0.0/16";
      # Lighthouses are now oracle + maitred (defined in hosts below)
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
    # GCE lighthouse (10.100.0.1) retired due to egress costs

    oracle = {
      ip = "10.100.0.2";
      external = "150.136.155.204:4242";
      isLighthouse = true;
      isRelay = true;
      role = "lighthouse";
      groups = ["lighthouse" "system-manager"];
      publicKey = null; # Managed via system-manager, not NixOS
      meta = {
        hardware = "Oracle Cloud VM (x86_64)";
        purpose = "External Nebula lighthouse + relay for redundancy";
        name = "Oracle cloud lighthouse";
        notes = "Managed via system-manager with agenix-compatible secrets";
      };
    };

    historian = {
      ip = "10.100.0.10";
      role = "desktop";
      groups = ["desktops" "nixos" "printing"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBXpuMSA1RXsYs6cEhvNqzhWpbIe2NB0ya1MUte87SD+";
      meta = {
        hardware = "Beelink SER5 Max (Ryzen 7 5800H APU)";
        purpose = "Daily driver desktop, future local AI inference";
        name = "Records and preserves - will run local AI models";
        notes = "Low-power gaming for now; waiting for ROCm support in NixOS";
      };
    };

    total-eclipse = {
      ip = "10.100.0.6";
      role = "desktop";
      groups = ["desktops" "nixos" "printing"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII25uGB19xLNzpzOFKUHp93EtNPxHXgeKotRDsdqdWa7";
      meta = {
        hardware = "Costco gaming PC (Nvidia RTX 4060 6GB)";
        purpose = "Gaming rig, GPU compute";
        name = "2024 total solar eclipse + Bonnie Tyler";
        notes = "Impulse Costco purchase; primary gaming machine";
      };
    };

    marshmallow = {
      ip = "10.100.0.4";
      role = "laptop";
      groups = ["laptops" "nixos" "printing"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILlKSgkr7eXGq9Lcg/5TfH9eudHLEP1q4zAvA8zhq9wh";
      meta = {
        hardware = "ThinkPad T490";
        purpose = "Favorite daily driver laptop";
        name = "Sweets naming theme for portables";
        notes = "Most-used laptop; reliable workhorse";
      };
    };

    bartleby = {
      ip = "10.100.0.3";
      role = "laptop";
      groups = ["laptops" "nixos" "printing"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGCZ/lfNz+FcRNwbRMeT658YOH0YdCgLRBn/bcegj7pi";
      meta = {
        hardware = "ThinkPad E131";
        purpose = "Beloved college laptop, light tasks";
        name = "Predates sweets theme; Melville's scrivener";
        notes = "Missouri school surplus; ancient but cherished";
      };
    };

    maitred = {
      ip = "10.100.0.50";
      lanIp = "192.168.69.1";
      isLighthouse = true;
      isRelay = true;
      external = "kimb.dev:4242";
      role = "router";
      groups = ["routers" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXJ4JeYtJiV8ltScewAu+N8KYLy+muo+mP07XznOzjX";
      meta = {
        hardware = "Datto 1000 (repurposed MSP appliance)";
        purpose = "Edge router, reverse proxy, services host";
        name = "The maître d' - manages network guests";
        notes = "Replaced Verizon router; TP-Link mesh runs in AP mode behind it";
      };
    };

    rich-evans = {
      ip = "10.100.0.40";
      role = "server";
      groups = ["servers" "cameras" "nixos"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOCXEs7zN0NNdWyZ9MJ4pI0R8RAPH6EFj3E2Qp2Xzc1k";
      meta = {
        hardware = "HP Mini PC";
        purpose = "General server, camera host";
        name = "RedLetterMedia's Rich Evans";
        notes = "Retired from HTPC duty; now handles cameras and general services";
      };
    };

    cheesecake = {
      ip = "10.100.0.5";
      role = "laptop";
      groups = ["laptops" "nixos" "printing"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAUR3569JGhcZTUeq0DGswOAikxDEe47QVm8JlgvGrY9";
      meta = {
        hardware = "Microsoft Surface Go 3";
        purpose = "Portable tablet/laptop";
        name = "Sweets naming theme - cheesecake";
        notes = "Intel-based tablet with KDE Plasma";
      };
    };

    donut = {
      ip = "10.100.0.7";
      role = "laptop";
      groups = ["laptops" "nixos" "gaming"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIACE7zBUEKURYTBMlod/8LMnfZ2xkq0x/iSnLGXQlFTP";
      meta = {
        hardware = "Steam Deck (Valve handheld)";
        purpose = "Portable gaming device with NixOS";
        name = "Sweets naming theme - donut";
        notes = "Jovian NixOS for SteamOS-compatible experience; managed via Colmena";
      };
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
