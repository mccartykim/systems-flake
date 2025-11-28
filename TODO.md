# Systems Flake Reorganization TODO

## Project Goals
- Create a more maintainable and modular NixOS configuration
- Reduce duplication across machine configs
- Improve secret management and security
- Better organize development environments
- Add testing and documentation

## High-Priority Tasks

### 1. Module System Implementation
- [ ] Create `modules/` directory structure
  - [ ] `nixos/` for NixOS-specific modules
  - [ ] `darwin/` for MacOS-specific modules
  - [ ] `home/` for home-manager modules
- [ ] Move common configurations into appropriate modules
- [ ] Create clear documentation for each module

### 2. Profile System Creation
- [ ] Create `profiles/` directory
- [ ] Define base profiles:
  - [ ] Personal machine baseline
  - [ ] Work machine baseline
  - [ ] Server baseline
  - [ ] Gaming setup
- [ ] Update machine configurations to use profiles

### 3. Configuration Organization
- [ ] Create `common/` directory for shared configs
- [ ] Implement proper user configuration structure
- [ ] Define custom options
- [ ] Organize custom packages

## Medium-Priority Tasks

### 4. Secrets Management
- [ ] Set up proper SOPS integration
- [ ] Organize secrets by category
- [ ] Document secret management procedures
- [ ] Create secure backup strategy

### 5. Container Management
- [ ] Organize container definitions
- [ ] Create shared container configurations
- [ ] Document container deployment process

### 6. Development Environment
- [ ] Create project templates
- [ ] Standardize development tools across machines
- [ ] Improve direnv integration

## Long-Term Goals

### 7. Testing Infrastructure
- [ ] Set up basic test framework
- [ ] Create tests for critical configurations
- [ ] Implement CI/CD pipeline

### 8. Documentation
- [ ] Create comprehensive system documentation
- [ ] Document maintenance procedures
- [ ] Create troubleshooting guide

### 9. Role-Based Configurations
- [ ] Define clear system roles
- [ ] Create role-specific configurations
- [ ] Document role requirements and purposes

### 10. Darwin Integration
- [ ] Improve MacOS configuration management
- [ ] Better integrate with homebrew
- [ ] Standardize cross-platform configurations

## Machine-Specific Improvements

### Rich-Evans (HP Server)
- [ ] Organize service configurations
- [ ] Improve monitoring setup
- [ ] Document backup procedures
- [ ] Review and optimize container setup

### Marshmallow (Daily Driver)
- [ ] Optimize development environment
- [ ] Review and update user configurations
- [ ] Document system maintenance

### Total-Eclipse (Gaming PC)
- [ ] Optimize gaming-specific configurations
- [ ] Review and update graphics settings
- [ ] Document gaming setup procedures

### Bartleby
- [ ] Address boot sector issues
- [ ] Optimize for low-resource usage
- [ ] Document special considerations

### MacBooks (Cronut & Work)
- [ ] Standardize cross-platform tools
- [ ] Improve Darwin-specific configurations
- [ ] Document MacOS-specific procedures

## Notes
- Keep modular structure in mind when adding new configurations
- Maintain backward compatibility during reorganization
- Document all major changes
- Consider creating migration guides for significant changes

## References
- [NixOS Wiki](https://nixos.wiki/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Darwin Documentation](https://github.com/LnL7/nix-darwin)
- [Flakes Documentation](https://nixos.wiki/wiki/Flakes)

---

# Home Assistant SSO via Authelia OIDC

## Context

This plan implements true Single Sign-On (SSO) for Home Assistant using Authelia as an OpenID Connect (OIDC) provider. Currently, Home Assistant is exposed via Caddy reverse proxy on maitred with Authelia protecting access, but users must authenticate twice (Authelia, then Home Assistant's built-in auth). This plan eliminates the double-login by having Home Assistant authenticate directly against Authelia via OIDC.

The implementation uses a hybrid declarative approach:
- **Authelia OIDC provider**: Fully declarative via NixOS module
- **Home Assistant custom component**: Mounted read-only from Nix store derivation
- **Home Assistant packages**: Mounted read-only for OIDC config
- **Home Assistant configuration.yaml**: Bootstrapped declaratively on first boot, then mutable at runtime

This approach respects Home Assistant's need for mutable config while keeping as much as possible in Nix.

---

## Part 1: Authelia OIDC Provider (maitred)

### 1.1 Generate OIDC Secrets

Authelia needs two secrets for OIDC:
- **HMAC secret**: For signing tokens (32+ bytes, base64 encoded)
- **JWKS private key**: RSA or ECDSA key for JWT signing

```bash
# Generate HMAC secret
openssl rand -base64 32 > /tmp/authelia-oidc-hmac-secret

# Generate RSA private key for JWKS
openssl genrsa -out /tmp/authelia-oidc-jwks-key.pem 4096
```

### 1.2 Add Secrets to Agenix

In `secrets/secrets.nix`, add:
```nix
"authelia-oidc-hmac-secret.age".publicKeys = workingMachines;
"authelia-oidc-jwks-key.age".publicKeys = workingMachines;
```

Then encrypt:
```bash
cd secrets
agenix -e authelia-oidc-hmac-secret.age < /tmp/authelia-oidc-hmac-secret
agenix -e authelia-oidc-jwks-key.age < /tmp/authelia-oidc-jwks-key.pem
```

### 1.3 Update `hosts/maitred/authelia.nix`

Add the OIDC secrets to `age.secrets`:
```nix
authelia-oidc-hmac-secret = {
  file = ../../secrets/authelia-oidc-hmac-secret.age;
  mode = "0400";
  owner = "authelia-main";
  group = "authelia-main";
};

authelia-oidc-jwks-key = {
  file = ../../secrets/authelia-oidc-jwks-key.age;
  mode = "0400";
  owner = "authelia-main";
  group = "authelia-main";
};
```

Add OIDC provider configuration to `services.authelia.instances.main.settings`:
```nix
identity_providers.oidc = {
  authorization_policies = {
    default = {
      default_policy = "two_factor";
    };
  };
  clients = [
    {
      client_id = "homeassistant";
      client_name = "Home Assistant";
      public = true;  # No client secret needed
      authorization_policy = "default";
      redirect_uris = [ "https://hass.kimb.dev/auth/oidc/callback" ];
      scopes = [ "openid" "profile" "email" "groups" ];
      token_endpoint_auth_method = "none";
    }
  ];
};
```

Add secrets references to the existing `secrets` block:
```nix
secrets = {
  jwtSecretFile = config.age.secrets.authelia-jwt-secret.path;
  sessionSecretFile = config.age.secrets.authelia-session-secret.path;
  storageEncryptionKeyFile = config.age.secrets.authelia-storage-key.path;
  oidcHmacSecretFile = config.age.secrets.authelia-oidc-hmac-secret.path;
  oidcIssuerPrivateKeyFile = config.age.secrets.authelia-oidc-jwks-key.path;
};
```

---

## Part 2: Home Assistant OIDC Integration (rich-evans)

### 2.1 Create Home Assistant Module

Create `hosts/rich-evans/home-assistant.nix`:

```nix
{ pkgs, config, lib, ... }:
let
  yamlFormat = pkgs.formats.yaml {};
  cfg = config.kimb;

  # Fetch the OIDC custom component
  hass-oidc-auth = pkgs.fetchFromGitHub {
    owner = "christiaangoossens";
    repo = "hass-oidc-auth";
    rev = "main";  # TODO: pin to a specific release tag
    hash = "";     # TODO: get hash via nix-prefetch-github
  };

  # Declarative Home Assistant base configuration
  hassConfig = {
    homeassistant = {
      name = "Home";
      unit_system = "metric";
      time_zone = "America/New_York";
      packages = "!include_dir_named packages";
    };
    default_config = {};
    http = {
      use_x_forwarded_for = true;
      trusted_proxies = [
        "10.100.0.50"      # maitred via Nebula
        "192.168.100.1"    # maitred container bridge
      ];
    };
  };

  # OIDC package configuration (mounted read-only)
  oidcPackage = {
    auth_oidc = {
      client_id = "homeassistant";
      discovery_url = "https://auth.${cfg.domain}/.well-known/openid-configuration";
    };
  };

  # Generated files
  generatedConfig = yamlFormat.generate "configuration.yaml" hassConfig;
  generatedOidcPackage = yamlFormat.generate "oidc.yaml" oidcPackage;
in {
  # Bootstrap service - copies declarative config on first boot only
  systemd.services.hass-config-bootstrap = {
    description = "Bootstrap Home Assistant configuration";
    wantedBy = [ "podman-homeassistant.service" ];
    before = [ "podman-homeassistant.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/hass/packages
      mkdir -p /var/lib/hass/custom_components

      if [ ! -f /var/lib/hass/configuration.yaml ]; then
        echo "Bootstrapping Home Assistant configuration..."
        cp ${generatedConfig} /var/lib/hass/configuration.yaml
        chmod 644 /var/lib/hass/configuration.yaml
      fi
    '';
  };

  # Home Assistant container
  virtualisation.oci-containers.containers.homeassistant = lib.mkIf cfg.services.homeassistant.enable {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    autoStart = true;

    volumes = [
      "/var/lib/hass:/config"
      # Mount OIDC package (always current, read-only)
      "${generatedOidcPackage}:/config/packages/oidc.yaml:ro"
      # Mount custom component (always current, read-only)
      "${hass-oidc-auth}/custom_components/auth_oidc:/config/custom_components/auth_oidc:ro"
    ];

    environment = {
      TZ = "America/New_York";
    };

    extraOptions = [
      "--privileged"
      "--network=host"
    ];
  };

  # Enable podman backend
  virtualisation.oci-containers.backend = lib.mkIf cfg.services.homeassistant.enable "podman";
  virtualisation.podman.enable = lib.mkIf cfg.services.homeassistant.enable true;

  # Firewall for Home Assistant
  networking.firewall.allowedTCPPorts = lib.mkIf cfg.services.homeassistant.enable [
    cfg.services.homeassistant.port
  ];
}
```

### 2.2 Get the hass-oidc-auth Hash

Run this to get the hash for the fetchFromGitHub:
```bash
nix-prefetch-github christiaangoossens hass-oidc-auth --rev main
```

Or for a specific release tag (check the repo for latest):
```bash
nix-prefetch-github christiaangoossens hass-oidc-auth --rev v0.3.0
```

Update the `hash` field in the derivation with the result.

### 2.3 Update `hosts/rich-evans/configuration.nix`

Add the new module to imports:
```nix
imports = [
  # ... existing imports
  ./home-assistant.nix
];
```

### 2.4 Update `hosts/rich-evans/services.nix`

Remove the existing `virtualisation.oci-containers.containers.homeassistant` block since it's now in `home-assistant.nix`. Keep the other services (copyparty, homepage, firewall rules for non-HA services).

---

## Part 3: Update Service Definitions (flake.nix)

### 3.1 Change Home Assistant Auth Type

In `flake.nix`, the maitred homeassistant service definition should use `auth = "none"` since OIDC handles authentication directly (not via Authelia forward_auth):

```nix
homeassistant = {
  enable = true;
  port = 8123;
  subdomain = "hass";
  host = "rich-evans";
  auth = "none";  # OIDC handles auth, not Authelia forward_auth
  publicAccess = true;
  websockets = true;
};
```

Note: This removes the Authelia forward_auth from Caddy. Home Assistant will redirect to Authelia's OIDC flow itself.

---

## Part 4: Testing & Deployment

### 4.1 Build Configurations

```bash
# Build both hosts
nixos-rebuild build --flake .#maitred
nixos-rebuild build --flake .#rich-evans
```

### 4.2 Deploy

```bash
# Deploy maitred first (Authelia OIDC provider)
nix develop -c colmena apply --on maitred

# Then deploy rich-evans (Home Assistant)
nix develop -c colmena apply --on rich-evans
```

### 4.3 First-Time Home Assistant Setup

1. Access `https://hass.kimb.dev`
2. Home Assistant should show the OIDC login option
3. Click to authenticate via Authelia
4. Complete Authelia 2FA if configured
5. Home Assistant creates/links the user account

### 4.4 Reset to Declarative Config (if needed)

If you want to reset Home Assistant's configuration.yaml to the declarative version:
```bash
ssh rich-evans
sudo rm /var/lib/hass/configuration.yaml
sudo systemctl restart podman-homeassistant
```

---

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `secrets/secrets.nix` | Modify | Add OIDC secret definitions |
| `secrets/authelia-oidc-hmac-secret.age` | Create | HMAC signing secret |
| `secrets/authelia-oidc-jwks-key.age` | Create | RSA private key for JWT |
| `hosts/maitred/authelia.nix` | Modify | Add OIDC provider config |
| `hosts/rich-evans/home-assistant.nix` | Create | New HA module with bootstrap |
| `hosts/rich-evans/services.nix` | Modify | Remove old HA container config |
| `hosts/rich-evans/configuration.nix` | Modify | Import new HA module |
| `flake.nix` | Modify | Change HA auth to "none" |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────┬───────────────────────────────────────┘
                          │ HTTPS (443)
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    maitred (router)                              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              Caddy (reverse-proxy container)                ││
│  │    hass.kimb.dev → socat → rich-evans:8123                  ││
│  │    auth.kimb.dev → authelia:9091                            ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Authelia                                 ││
│  │    - Forward auth for other services                        ││
│  │    - OIDC Provider for Home Assistant                       ││
│  │      └─ Client: homeassistant (public)                      ││
│  │      └─ Callback: hass.kimb.dev/auth/oidc/callback          ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────┬───────────────────────────────────────┘
                          │ Nebula (10.100.0.0/16)
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   rich-evans (server)                            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              Home Assistant (container)                     ││
│  │    Port: 8123                                               ││
│  │    Auth: OIDC via hass-oidc-auth component                  ││
│  │                                                             ││
│  │    Mounted (read-only from Nix store):                      ││
│  │      /config/custom_components/auth_oidc/                   ││
│  │      /config/packages/oidc.yaml                             ││
│  │                                                             ││
│  │    Bootstrapped (mutable):                                  ││
│  │      /config/configuration.yaml                             ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Authentication Flow

```
User visits hass.kimb.dev
         │
         ▼
    Caddy proxy
         │
         ▼
   Home Assistant
         │
         ▼
   No session? ──────► Redirect to Authelia OIDC
         │                      │
         │                      ▼
         │              Authelia login
         │              (username + 2FA)
         │                      │
         │                      ▼
         │              Authelia issues
         │              OIDC token
         │                      │
         ◄──────────────────────┘
         │              Callback to HA
         ▼
   Home Assistant
   validates token,
   creates/links user
         │
         ▼
   User logged in!
```