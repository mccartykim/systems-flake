# systems-flake Architecture Reference

## 1. Overview

This flake manages NixOS configurations for a personal network of desktops, laptops, servers, and embedded devices. All hosts connect via Nebula mesh VPN.

## 2. Data Model

### 2.1 Host Registry

`hosts/nebula-registry.nix` is the authoritative source for all host data.

**Schema:**
```
hosts.<name> = {
  ip         : string      # Nebula IP (10.100.0.0/16)
  role       : enum        # desktop | laptop | server | router | camera
  groups     : [string]    # Nebula firewall groups
  publicKey  : string      # SSH host ed25519 public key
  lanIp?     : string      # Optional LAN IP (for routers)
  external?  : string      # External endpoint (for lighthouse)
  meta?      : {           # Optional metadata for documentation/context
    hardware : string      # Physical hardware description
    purpose  : string      # What the host is used for
    name     : string      # Why it's named this way
    notes    : string      # Additional context
  }
}
```

**Derived exports:**
- `nodes` - All hosts
- `nixosHosts` - Hosts excluding lighthouse
- `hostKeys` - SSH public keys for agenix
- `networks` - Network infrastructure (subnets, DHCP, containers)

### 2.2 SSH Keys

`hosts/ssh-keys.nix` derives host keys from the registry and adds user keys.

- `host` - Host SSH keys (from registry)
- `user` - User SSH keys (for authorized_keys)
- `authorizedKeys` - List of user keys
- `bootstrap` - Key for agenix re-encryption

### 2.3 Secrets

`secrets/secrets.nix` defines agenix encryption rules.

Secrets are auto-generated for all hosts in the registry:
- `nebula-<host>-cert.age` - Nebula certificate
- `nebula-<host>-key.age` - Nebula private key

**Usage:**
```bash
cd /path/to/repo
agenix -e secrets/new-secret.age
```

Note: The `secrets.nix` symlink at repo root is required by agenix CLI.

## 3. Module Architecture

### 3.1 Nebula Configuration

`modules/nebula-node.nix` provides consolidated Nebula mesh configuration.

**Options:**
```nix
kimb.nebula = {
  enable              : bool            # Enable nebula mesh
  openToPersonalDevices : bool          # Allow all from desktops/laptops
  extraInboundRules   : [rule]          # Additional firewall rules
};
```

**Rule schema:**
```nix
{ port = 8080; proto = "tcp"; host = "any"; }
{ port = 8555; proto = "udp"; groups = ["desktops" "laptops"]; }
```

### 3.2 Service Topology

`modules/kimb-services.nix` defines service metadata for reverse proxy generation.

**Options:**
```nix
kimb.services.<name> = {
  enable        : bool
  port          : int
  subdomain     : string
  host          : string    # Host running the service
  container     : bool      # Whether in NixOS container
  auth          : string    # "none" | "authelia" | "builtin"
  publicAccess  : bool
  websockets    : bool
};
```

## 4. Flake Structure

### 4.1 Helper Functions

Defined in `flake.nix`:

**mkDesktop** - Desktop/laptop configurations
```nix
mkDesktop {
  hostname        : string          # Required
  system?         : string          # Default: "x86_64-linux"
  extraModules?   : [module]        # Additional modules
  hardwareModules?: [module]        # Hardware-specific modules
  homeConfig?     : path            # Default: ./home/${hostname}.nix
  useGlobalPkgs?  : bool            # Default: false
}
```

**mkServer** - Server configurations
```nix
mkServer {
  hostname         : string
  system?          : string
  extraModules?    : [module]
  extraSpecialArgs?: attrset
}
```

### 4.2 Module Lists

- `commonModules` - Applied to all: nix-index-database
- `desktopModules` - srvos.desktop + mixins
- `serverModules` - srvos.server + mixins

### 4.3 Checks

Available via `nix flake check`:
- `minimal-test` - Basic VM boot
- `network-test` - Multi-VM network test
- `eval-<hostname>` - Configuration evaluation

## 5. Adding a New Host

### 5.1 Desktop

1. Add to registry:
```nix
# hosts/nebula-registry.nix
new-host = {
  ip = "10.100.0.XX";
  role = "desktop";
  groups = ["desktops" "nixos"];
  publicKey = "ssh-ed25519 ...";  # from target's /etc/ssh/ssh_host_ed25519_key.pub
};
```

2. Create configuration:
```nix
# hosts/new-host/configuration.nix
{ config, pkgs, inputs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/desktop.nix
    ../../modules/nebula-node.nix
  ];

  kimb.nebula.enable = true;
  networking.hostName = "new-host";
  system.stateVersion = "24.11";
}
```

3. Create home config:
```nix
# home/new-host.nix
{ ... }: {
  imports = [ ./default.nix ];
  home.stateVersion = "24.11";
}
```

4. Add to flake:
```nix
new-host = mkDesktop { hostname = "new-host"; };
```

5. Generate secrets:
```bash
# Generate nebula certs externally, then:
agenix -e secrets/nebula-new-host-cert.age
agenix -e secrets/nebula-new-host-key.age
```

### 5.2 Server

Same as above, but use `mkServer` and `profiles/server.nix`.

## 6. Deployment

### 6.1 Local

```bash
nixos-rebuild build --flake .#hostname
nixos-rebuild switch --flake .#hostname
```

### 6.2 Remote (Colmena)

```bash
nix develop -c colmena apply --on hostname
nix develop -c colmena apply  # All hosts
```

Colmena uses Nebula IPs from the registry via `${hostname}.nebula` DNS.

## 7. Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                     Nebula Mesh (10.100.0.0/16)             │
│                                                              │
│  lighthouse ─────────────────────────────────────────────   │
│  (10.100.0.1)                                               │
│       │                                                      │
│       ├── historian (10.100.0.10) [desktop]                 │
│       ├── total-eclipse (10.100.0.6) [desktop]              │
│       ├── marshmallow (10.100.0.4) [laptop]                 │
│       ├── bartleby (10.100.0.3) [laptop]                    │
│       ├── maitred (10.100.0.50) [router] ─┐                 │
│       │         │                          │                 │
│       │         └── LAN (192.168.69.0/24)  │                 │
│       │                                    │                 │
│       │         Containers (192.168.100.0/24)               │
│       │         ├── reverse-proxy (.2)                      │
│       │         ├── blog-service (.3)                       │
│       │         └── authelia (.4)                           │
│       │                                                      │
│       ├── rich-evans (10.100.0.40) [server]                 │
│       └── arbus (10.100.0.20) [camera]                      │
└─────────────────────────────────────────────────────────────┘
```

## 8. File Reference

```
flake.nix                          # Entry point
hosts/
  nebula-registry.nix             # Host data (single source of truth)
  ssh-keys.nix                    # SSH keys (derives from registry)
  profiles/
    base.nix                      # All hosts
    desktop.nix                   # Desktop/laptop
    laptop.nix                    # Laptop-specific
    server.nix                    # Server
    gaming.nix                    # Gaming overlay
    i3-desktop.nix                # i3 window manager
  <hostname>/
    configuration.nix             # Host config
    hardware-configuration.nix    # Generated hardware
modules/
  nebula-node.nix                 # Nebula mesh module
  kimb-services.nix               # Service topology
home/
  default.nix                     # Shared home config
  <hostname>.nix                  # Per-host home
  modules/                        # Home-manager modules
secrets/
  secrets.nix                     # Agenix rules
  *.age                           # Encrypted secrets
darwin/
  <hostname>/configuration.nix    # macOS configs
tests/
  *.nix                           # VM tests
```

## Revision History

- 2025-11: Initial architecture documentation
- 2025-11: Consolidated nebula configs, added flake helpers, unified registry
