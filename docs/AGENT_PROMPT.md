# Agent Guidelines for systems-flake

## Context

This is a NixOS flake managing personal infrastructure. Read `ARCHITECTURE.md` first.

## Key Principles

1. **Single source of truth**: `hosts/nebula-registry.nix` for all host data
2. **DRY via helpers**: Use `mkDesktop`/`mkServer` in flake.nix
3. **Test before commit**: `nix flake check` or at minimum eval checks
4. **Conventional commits**: `feat(hostname):`, `fix(hostname):`, `refactor:`

## Common Tasks

### Add a host
1. Add to `hosts/nebula-registry.nix`
2. Create `hosts/<name>/configuration.nix`
3. Create `home/<name>.nix`
4. Add to `flake.nix` using `mkDesktop` or `mkServer`
5. Generate agenix secrets

### Modify nebula config
Edit `modules/nebula-node.nix` for global changes, or set `kimb.nebula.extraInboundRules` for host-specific rules.

### Add a service
Configure in `kimb.services.<name>` in the host's flake module entry. The service topology feeds into reverse proxy configuration.

### Update secrets
```bash
agenix -e secrets/name.age  # Uses symlinked secrets.nix at repo root
```

## Don't

- Don't duplicate host data (IPs, keys) outside the registry
- Don't create per-host nebula.nix files (use the module)
- Don't skip `nix flake check` for large changes
- Don't modify `secrets.nix` without re-encrypting affected files

## File Ownership

- `nebula-registry.nix` - Add hosts here only
- `ssh-keys.nix` - Add *user* keys here, host keys come from registry
- `secrets/secrets.nix` - Auto-generates nebula secrets from registry

## Testing

```bash
# Fast eval check
nix build .#checks.x86_64-linux.eval-historian

# Full VM test
nix build .#checks.x86_64-linux.network-test

# All checks
nix flake check
```

## When Updating This Repo

After significant changes, update:
1. `CLAUDE.md` - Quick reference for AI assistants
2. `docs/ARCHITECTURE.md` - Technical reference
3. This file if workflow changes
