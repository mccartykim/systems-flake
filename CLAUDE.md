# NixOS Systems-Flake Guidelines

## Build/Test Commands
- Build system: `nixos-rebuild build --flake .#<hostname>`
- Test system: `nixos-rebuild test --flake .#<hostname>`
- Apply changes: `nixos-rebuild switch --flake .#<hostname>`
- Darwin rebuild: `darwin-rebuild switch --flake .#<hostname>`
- Format code: `nix fmt` (using Alejandra formatter)
- Check flake: `nix flake check`

## Commit Conventions
Use conventional commits format:
```
<type>(<optional scope>): <description>

<optional body>

<optional footer>
```
- **Types**: feat, fix, refactor, perf, style, test, docs, build, ops, chore
- **Scope**: Usually the hostname (e.g., marshmallow, bartleby)
- **Example**: `feat(marshmallow): add hyprland configuration`

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