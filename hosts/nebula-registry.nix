# Authoritative Host Registry
# Single source of truth for HOST TOPOLOGY (IPs, roles, groups, hardware).
# All other files should reference this for IPs, roles, and groups.
#
# Pubkeys (host SSH keys + bootstrap user key) are NOT defined here — they
# live in the systems-flake-secrets flake at host-keys.nix and are injected
# via the `secretsFlake` argument so the recipient set for agenix and the
# pubkey table here can never drift apart.
#
# Naming conventions:
#   - Portables: sweets (marshmallow, cheesecake, cronut) *bartleby predates this
#   - Desktops/servers: references/puns (historian, total-eclipse, rich-evans)
#   - Infrastructure: roles (maitred, lighthouse)
{secretsFlake}: let
  hostKeyData = import (secretsFlake + "/host-keys.nix");
  inherit (hostKeyData) hostKeys systemManagerKeys bootstrap;

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

  # All managed hosts with complete configuration. publicKey is sourced
  # from the secrets flake so there's exactly one place to update it on
  # rotation.
  hosts = {
    # GCE lighthouse (10.100.0.1) retired due to egress costs

    oracle = {
      ip = "10.100.0.2";
      external = "150.136.155.204:4242";
      isLighthouse = true;
      isRelay = true;
      role = "lighthouse";
      groups = ["lighthouse" "system-manager"];
      # SSH key for agenix secrets (system-manager uses host SSH key, not NixOS)
      publicKey = systemManagerKeys.oracle;
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
      publicKey = hostKeys.historian;
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
      publicKey = hostKeys.total-eclipse;
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
      publicKey = hostKeys.marshmallow;
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
      publicKey = hostKeys.bartleby;
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
      publicKey = hostKeys.maitred;
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
      publicKey = hostKeys.rich-evans;
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
      publicKey = hostKeys.cheesecake;
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
      publicKey = hostKeys.donut;
      meta = {
        hardware = "Steam Deck (Valve handheld)";
        purpose = "Portable gaming device with NixOS";
        name = "Sweets naming theme - donut";
        notes = "Jovian NixOS for SteamOS-compatible experience; managed via Colmena";
      };
    };

    tachikoma = {
      ip = "10.100.0.60";
      role = "iot";
      groups = ["iot" "cameras"];
      publicKey = null; # Not NixOS, managed manually
      meta = {
        hardware = "Dreame vacuum with Valetudo";
        purpose = "Robot vacuum with camera";
        name = "Ghost in the Shell think-tank";
        notes = "Runs nebula via postboot script; certs in /data/nebula_cfg";
      };
    };

    mochi = {
      ip = "10.100.0.8";
      role = "mobile";
      groups = ["mobile" "system-manager"];
      publicKey = systemManagerKeys.mochi;
      meta = {
        hardware = "Google Pixel 9 Pro (AVF/Debian)";
        purpose = "Mobile phone with AVF Linux terminal";
        name = "Sweets naming theme - mochi";
        notes = "Managed via system-manager; nebula for mesh access";
      };
    };
  };

  # Helper: get all NixOS hosts (exclude lighthouse)
  nixosHosts = builtins.removeAttrs hosts ["lighthouse"];
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

  # SSH host keys (for agenix) — re-exported from the secrets flake so
  # callers that already use registry.hostKeys keep working.
  inherit hostKeys bootstrap;
}
