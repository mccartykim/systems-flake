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
      # Multiple lighthouses for redundancy
      lighthouses = {
        gce = {
          ip = "10.100.0.1";
          external = "35.222.40.201:4242";
        };
        maitred = {
          ip = "10.100.0.50";
          external = "kimb.dev:4242"; # Dynamic IP via DDNS
        };
      };
      # Legacy alias for backward compatibility during migration
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
      isRelay = true;
      role = "lighthouse";
      groups = ["lighthouse"];
      publicKey = null; # External Google Cloud instance
      meta = {
        hardware = "Google Cloud e2-micro";
        purpose = "Nebula coordination and relay";
        name = "The lighthouse that guides nebula connections";
        notes = "Manually configured, not NixOS-managed. Primary lighthouse in GCE.";
      };
    };

    historian = {
      ip = "10.100.0.10";
      role = "desktop";
      groups = ["desktops" "nixos"];
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
      groups = ["desktops" "nixos"];
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
      groups = ["laptops" "nixos"];
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
      groups = ["laptops" "nixos"];
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
      external = "kimb.dev:4242"; # Dynamic IP via DDNS
      isLighthouse = true;
      isRelay = true;
      role = "router";
      groups = ["routers" "nixos" "lighthouse"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXJ4JeYtJiV8ltScewAu+N8KYLy+muo+mP07XznOzjX";
      meta = {
        hardware = "Datto 1000 (repurposed MSP appliance)";
        purpose = "Edge router, reverse proxy, services host, nebula lighthouse";
        name = "The maître d' - manages network guests";
        notes = "Replaced Verizon router; TP-Link mesh runs in AP mode behind it. Also serves as secondary nebula lighthouse and relay.";
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
  };

  # Helper: filter hosts by role
  byRole = role: builtins.filter (h: h.role == role) (builtins.attrValues hosts);

  # Helper: get all NixOS hosts (exclude lighthouse)
  nixosHosts = builtins.removeAttrs hosts ["lighthouse"];

  # Helper: get all lighthouse hosts (hosts with isLighthouse = true)
  getLighthouses = builtins.filter (name: hosts.${name}.isLighthouse or false) (builtins.attrNames hosts);

  # Helper: get all relay hosts (hosts with isRelay = true)
  getRelays = builtins.filter (name: hosts.${name}.isRelay or false) (builtins.attrNames hosts);

  # Helper: build static host map for all lighthouses
  # Returns: { "10.100.0.1" = ["35.222.40.201:4242"]; "10.100.0.50" = ["kimb.dev:4242"]; }
  lighthouseStaticHostMap = builtins.listToAttrs (
    map (name: {
      name = hosts.${name}.ip;
      value = [hosts.${name}.external];
    }) getLighthouses
  );

  # Helper: get list of lighthouse IPs
  lighthouseIPs = map (name: hosts.${name}.ip) getLighthouses;

  # Helper: get list of relay IPs
  relayIPs = map (name: hosts.${name}.ip) getRelays;

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

  # Nebula lighthouse/relay configuration
  inherit lighthouseStaticHostMap lighthouseIPs relayIPs;

  # SSH host keys (for agenix)
  hostKeys = getPublicKeys nixosHosts;

  # Bootstrap key for agenix re-encryption (cheesecake user key)
  bootstrap = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQgFzMg37QTeFE2ybQRHfVEQwW/Wz7lK6jPPmctFd/U";
}
