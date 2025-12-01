# NixOS Systems-Flake Guidelines

## Build/Test Commands
- Build system: `nixos-rebuild build --flake .#<hostname>`
- Test system: `nixos-rebuild test --flake .#<hostname>`
- Apply changes: `nixos-rebuild switch --flake .#<hostname>`
- Darwin rebuild: `darwin-rebuild switch --flake .#<hostname>`
- Format code: `nix fmt` (using Alejandra formatter)
- Check flake: `nix flake check`

## Version Control
- **VCS**: This repository uses Jujutsu (jj) for version control
- **Workflow**: Working-copy-as-commit model - changes are automatically tracked
- **Commands**: Use `jj` instead of `git` commands

## Jujutsu (jj) Workflow

### Core Concepts
- **Working Copy as Commit**: Your working directory is an actual commit that gets automatically amended
- **Change IDs**: Stable identifiers that persist across rebases and amendments
- **Automatic Commits**: Every `jj` command automatically commits working copy changes

### Essential Commands

#### Viewing Changes
```bash
jj status                      # Show working copy status
jj log                         # Show commit history
jj log -n 5                    # Show last 5 commits
jj show @ --git                # Show current commit with diff
jj show -r <change-id> --git   # Show specific commit
jj diff --git                  # Show working copy diff
jj diff --no-pager --git       # Without pager for scripting
```

#### Creating Commits
```bash
jj describe -m "message"       # Add description to working copy
jj new                         # Create new empty commit (child of current)
jj new -m "message"            # Create new commit with message (start new feature)
jj commit -m "message"         # Describe and create new child commit
```

**Starting a New Feature**:
```bash
# Create a new commit with intent before making changes
jj new -m "feat(hostname): add new feature"
# Now make your changes - they'll go into this commit
```

#### Splitting Commits
The `jj split` command is crucial for creating atomic commits:

```bash
# Split specific files into new commit
jj split file1.nix file2.nix -m "commit message"

# Split interactively (requires terminal)
jj split -i

# Split with tool
jj split --tool <editor>
```

**Pattern for Atomic Commits**:
1. Make all related changes in working copy
2. Use `jj split` to separate into logical commits
3. Verify with `jj show` that each commit contains correct changes
4. Each commit should have single responsibility

**Example Session**:
```bash
# Make multiple changes across files
vim hosts/maitred/configuration.nix
vim hosts/maitred/authelia.nix

# Split into separate commits
jj split hosts/authelia.nix -m "feat(maitred): add Authelia SSO"
# Working copy now only has configuration.nix changes
jj describe -m "feat(maitred): add DNS entry for service"

# Verify commits are correct
jj show @ --git
jj show @- --git
```

#### Fixing Commits
```bash
# Edit a specific commit (move working copy to that commit)
jj edit -r <change-id>

# Split or modify, then return to latest
jj edit -r @     # or the latest change-id

# Squash working copy into parent
jj squash

# Describe/rename a commit
jj describe -r <change-id> -m "new message"
```

#### Useful Flags
- `--no-pager`: Disable pager for scripting
- `--git`: Show diffs in git format
- `-r <revset>`: Specify revision (change-id, @, @-, @--, etc.)
- `-n <number>`: Limit number of results

### Atomic Commit Guidelines

**What Makes a Good Atomic Commit**:
1. **Single Logical Change**: One feature, bug fix, or refactor per commit
2. **Self-Contained**: Commit should build and work independently
3. **Correct Scope**: Scope matches files changed (e.g., don't mix maitred + historian)
4. **Clear Message**: Conventional commit format with descriptive body

**Common Splitting Scenarios**:
- Separate deprecation fixes from new features
- Split configuration changes by host
- Separate related but independent changes (DHCP + DNS entries)
- Split refactoring from new functionality
- Separate build fixes from feature changes

**Verification Pattern**:
```bash
# After splitting, verify each commit
jj log -n 5                          # See commit structure
jj show -r <each-change-id> --git    # Verify content of each

# Check commit messages match content
jj log --no-graph -n 5               # See just the messages

# Build test specific commit
jj edit -r <change-id>
nixos-rebuild build --flake .#hostname
jj edit -r @  # Return to latest
```

### Best Practices
1. **Split Early**: It's easier to split as you go than to fix later
2. **Verify Often**: Use `jj show` to check commits are atomic
3. **Use Change IDs**: More stable than commit hashes
4. **Test Builds**: Each commit should build successfully
5. **Descriptive Messages**: Follow conventional commits format
6. **Clean History**: Use `jj edit` and `jj split` to fix mistakes

## Commit Conventions
Use conventional commits format:
```
<type>(<optional scope>): <description>

<optional body>

<optional footer>
```
- **Types**: feat, fix, refactor, perf, style, test, docs, build, ops, chore
- **Scope**: Usually the hostname (e.g., marshmallow, bartleby, historian)
- **Examples**: 
  - `feat(historian): upgrade to kernel 6.14 for AMD VCN fixes`
  - `fix(marshmallow): resolve hyprland configuration issue`

## Code Style Guidelines
- **Formatting**: Use Alejandra (configured as formatter in flake.nix)
- **Structure**: 
  - Host-specific configs in `hosts/<hostname>/`
  - Home-manager configs in `home/`
  - Darwin configs in `darwin/`
- **Naming**: Use descriptive names for hosts and configuration files
- **Imports**: Prefer modules over imports when comfortable
- **Nix Style**: 
  - Use `let ... in` for local variables
  - Use attribute sets for configuration
- **Testing**: Test configurations before pushing with `nixos-rebuild build`

## Deployment
- **Tool**: Use Colmena for multi-host deployments
- **Commands**:
  - Deploy single host: `nix develop -c colmena apply --on <hostname>`
  - Deploy all: `nix develop -c colmena apply`
- **Network**: Colmena uses Nebula mesh network IPs for direct deployment (except maitred)

## System-Manager for Non-NixOS Hosts

For non-NixOS hosts (e.g., Ubuntu VMs), use [numtide/system-manager](https://github.com/numtide/system-manager) to manage systemd services and /etc files declaratively.

### Building and Deploying
```bash
# Build the system-manager config
nix build .#systemConfigs.oracle

# Copy closure to remote host
nix copy --to ssh://user@host ./result

# Activate on remote host
ssh user@host "sudo /nix/store/...-system-manager/bin/activate"
```

### Agenix-Compatible Secrets Pattern
System-manager lacks `system.activationScripts`, so use a systemd oneshot service to decrypt secrets:

```nix
# Place encrypted secrets in /etc (from Nix store - safe, they're encrypted)
environment.etc."service/encrypted/secret.age".source = ../../secrets/secret.age;

# Oneshot service decrypts before main service starts
systemd.services.decrypt-secrets = {
  description = "Decrypt secrets";
  wantedBy = ["multi-user.target"];
  before = ["main.service"];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = pkgs.writeShellScript "decrypt" ''
      ${pkgs.age}/bin/age -d -i /etc/ssh/ssh_host_ed25519_key \
        -o /run/secrets/decrypted \
        /etc/service/encrypted/secret.age
    '';
  };
};

systemd.services.main = {
  requires = ["decrypt-secrets.service"];
  after = ["decrypt-secrets.service"];
  # ...
};
```

### Current System-Manager Hosts
- **oracle**: Nebula lighthouse at 10.100.0.2 (Oracle Cloud Ubuntu VM)

## Container Architecture Patterns

### NixOS Container Separation
- **Pattern**: Use NixOS containers for service isolation and separation of concerns
- **Example**: maitred router with reverse-proxy + blog-service containers
- **Benefits**: Clean separation, easier debugging, isolated failure domains
- **Network**: Use private networks with NAT for internet access

### Container Networking
```nix
# Essential for container internet access
networking.nat.internalInterfaces = [ "ve-+" ];

# Container bridge setup
containers.service-name = {
  privateNetwork = true;
  hostAddress = "192.168.100.1";    # Host bridge IP
  localAddress = "192.168.100.2";   # Container IP
};

# Port forwarding from host to container
networking.nat.forwardPorts = [
  { sourcePort = 80; destination = "192.168.100.2:80"; proto = "tcp"; }
];
```

## Reverse Proxy + HTTPS Patterns

### Caddy Configuration
- **Auto HTTPS**: Caddy automatically handles Let's Encrypt certificates
- **Wildcard Certs**: Single domain (e.g., kimb.dev) covers all subdomains
- **Access Control**: Use IP-based restrictions for internal services

```nix
services.caddy = {
  enable = true;
  email = "your-email@domain.com";
  virtualHosts = {
    "domain.com" = {
      extraConfig = ''reverse_proxy container-ip:port'';
    };
    "internal.domain.com" = {
      extraConfig = ''
        @allowed {
          remote_ip 192.168.0.0/16 10.0.0.0/8 100.64.0.0/10
        }
        handle @allowed {
          reverse_proxy service-ip:port
        }
        handle {
          respond "Access denied" 403
        }
      '';
    };
  };
};
```

### Network Access Control
- **LAN**: `192.168.0.0/16` (local network)
- **Nebula**: `10.100.0.0/16` (mesh VPN)
- **Tailscale**: `100.64.0.0/10` (backup VPN)

## Secret Management with Agenix

### Bootstrap Pattern for Certificate Re-encryption
**Problem**: When agenix certificates are encrypted with old/missing SSH keys, causing "no identity matched any of the recipients" errors.

**Solution**: Bootstrap re-encryption using user SSH key:
1. **Add user SSH key temporarily** to `secrets.nix`:
   ```nix
   myUserKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...";
   workingMachines = [
     registry.nodes.historian.publicKey
     # ... other host keys
     myUserKey  # Temporary for bootstrap
   ];
   ```

2. **Remove old encrypted files** and create fresh ones:
   ```bash
   rm nebula-ca.age
   cat /path/to/source/ca.crt | agenix -e nebula-ca.age -i ~/.ssh/id_ed25519
   ```

3. **Remove user key** from `secrets.nix` after re-encryption
4. **Deploy with colmena** - certificates should now decrypt with host SSH keys

**Key Requirements**:
- Configure `age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];` in NixOS config
- Use `agenix -e FILE -i IDENTITY` for manual encryption with specific keys
- Host must have `/etc/ssh/ssh_host_ed25519_key` readable by agenix (usually via sudo/root)

### Pattern for Dynamic Configuration
```nix
# Use activation scripts to read agenix secrets into config files
system.activationScripts.service-config = lib.stringAfter [ "agenix" ] ''
  secret=$(cat "${config.age.secrets.api-token.path}")
  mkdir -p /etc/service
  cat > /etc/service/config << EOF
  api_token = $secret
  EOF
  chmod 600 /etc/service/config
'';
```

### Secret Definition
```nix
age.secrets.api-token = {
  file = ../../secrets/api-token.age;
  path = "/etc/service/token";
  mode = "0400";
  owner = "service-user";
  group = "service-group";
};
```

## Monitoring Stack Integration

### Prometheus + Grafana + Homepage
- **Prometheus**: Metrics collection on port 9090
- **Grafana**: Visualization on port 3000
- **Homepage**: Service portal on port 8082
- **Access**: All monitoring services behind Caddy with access control

### Service Discovery
```nix
services.prometheus = {
  scrapeConfigs = [
    {
      job_name = "node-exporter";
      static_configs = [{ targets = [ "localhost:9100" ]; }];
    }
    {
      job_name = "caddy";
      static_configs = [{ targets = [ "container-ip:2019" ]; }];
    }
  ];
};
```

## DNS Management

### Dynamic DNS with Inadyn
- **Single Domain**: Only update main domain (subdomains resolve automatically)
- **Cloudflare**: Use zone name as username, API token as password
- **Security**: Store tokens in agenix, read in activation scripts

```nix
provider cloudflare.com {
    username = domain.com        # Zone name
    password = $api_token        # From agenix
    hostname = domain.com        # Main domain only
    ttl = 1
    proxied = false
}
```

## Architecture

### Key Files
```
hosts/nebula-registry.nix      # Single source of truth for hosts (IPs, keys, roles)
hosts/ssh-keys.nix             # Derives from registry, adds user keys
hosts/oracle/configuration.nix # System-manager config for non-NixOS lighthouse
secrets/secrets.nix            # Derives from registry, auto-generates nebula secrets
modules/nebula-node.nix        # Consolidated nebula config module
modules/distributed-builds.nix # Remote builds via historian
modules/kimb-services.nix      # Service topology options
flake.nix                      # Uses mkDesktop/mkServer helpers + systemConfigs
```

### Host Registry (nebula-registry.nix)
All host data lives here. To add a new host:
```nix
hosts = {
  new-host = {
    ip = "10.100.0.XX";
    role = "desktop";  # desktop, laptop, server, router, camera
    groups = ["desktops" "nixos"];
    publicKey = "ssh-ed25519 AAAA...";  # from /etc/ssh/ssh_host_ed25519_key.pub
  };
};
```

### flake.nix Helper Functions
- **mkDesktop**: Desktops/laptops with home-manager + srvos.desktop
- **mkServer**: Servers with srvos.server modules
- **commonModules**: nix-index-database, distributed-builds (applied to all)
- **mkHomeManager**: Home-manager setup helper

Add a new desktop:
```nix
new-host = mkDesktop {
  hostname = "new-host";
  hardwareModules = [ nixos-hardware.nixosModules.some-hardware ];
  extraModules = [ ./modules/something.nix ];
};
```

### Nebula Configuration
Hosts use `modules/nebula-node.nix`:
```nix
imports = [ ../../modules/nebula-node.nix ];
kimb.nebula = {
  enable = true;
  openToPersonalDevices = true;  # Allow all ports from desktops/laptops
  extraInboundRules = [          # Host-specific firewall rules
    { port = 8080; proto = "tcp"; host = "any"; }
  ];
};
```

**LAN Discovery**: Nebula is configured to prefer direct LAN connections (192.168.69.0/24) over relay routing for lower latency between local hosts.

### Distributed Builds
Hosts use `modules/distributed-builds.nix` to offload builds to historian:
```nix
# Enabled by default in commonModules
kimb.distributedBuilds = {
  enable = true;       # Use historian as remote builder
  connectTimeout = 10; # Seconds before fallback to local build
  maxJobs = 8;         # Parallel jobs on historian
  speedFactor = 2;     # Prefer historian when available
};
```

**How it works**:
- Clients automatically try historian first for builds
- Falls back to local build after 10s timeout if historian unreachable
- Uses host SSH keys for authentication (no extra key management)
- Historian must be deployed first to accept client connections

### Testing
```bash
nix flake check                              # Run all checks
nix build .#checks.x86_64-linux.minimal-test # Run specific test
nix build .#checks.x86_64-linux.eval-historian # Eval check (fast)
```

### Host Roles
- **Desktops**: srvos.desktop, home-manager, gaming/development profiles
- **Laptops**: Same as desktops + power management
- **Servers**: srvos.server, kimb-services for service topology (rich-evans also handles cameras)
- **Routers**: Minimal, custom networking (maitred)
- **Lighthouses**: Nebula lighthouses/relays, may be non-NixOS (oracle via system-manager)

### Directory Structure
```
hosts/
  <hostname>/configuration.nix  # Host config
  profiles/                     # Shared profiles (base, desktop, server, etc.)
  nebula-registry.nix          # Host data registry
home/<hostname>.nix            # Home-manager per host
modules/                       # Custom NixOS modules
secrets/                       # Agenix secrets
darwin/                        # macOS configs
tests/                         # NixOS VM tests
```

### Network Topology
- **Nebula Mesh**: 10.100.0.0/16 - overlay network
- **LAN**: 192.168.69.0/24 - local network
- **Containers**: 192.168.100.0/24 - maitred containers
- **Tailscale**: 100.64.0.0/10 - backup connectivity

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.