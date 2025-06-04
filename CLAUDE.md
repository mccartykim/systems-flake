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