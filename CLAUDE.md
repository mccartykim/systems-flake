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
- **Nebula**: `10.100.0.0/24` (mesh VPN)
- **Tailscale**: `100.64.0.0/10` (backup VPN)

## Secret Management with Agenix

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

## Architecture Insights

### Host Roles
- **Servers**: Use srvos modules for hardening and optimization
- **Desktops**: Include home-manager for user environments
- **Routers**: Minimal base profile with networking focus
- **Darwin**: Separate configs for macOS systems

### Modular Design
- **Profiles**: Shared configurations in `hosts/profiles/`
- **Modules**: Reusable components in `modules/`
- **Secrets**: Centralized agenix secrets in `secrets/`
- **Home**: User environments in `home/`

### Network Architecture
- **Nebula Mesh**: All hosts connected via overlay network
- **Router Gateway**: maitred as internet gateway with containers
- **Service Exposure**: Public services via reverse proxy, private via access control
- **Backup Access**: Tailscale for redundant connectivity

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.