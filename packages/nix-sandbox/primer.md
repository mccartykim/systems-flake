# Nix Primer for Claude Code

## Research Resources

### Package & Option Search
- **Package search**: https://search.nixos.org/packages (search by name, browse by category)
- **Option search**: https://search.nixos.org/options (NixOS module options, e.g. `services.nginx.enable`)
- **Home Manager options**: https://home-manager-options.extranix.com/

### Source Code (the real documentation)
- **nixpkgs master**: https://github.com/NixOS/nixpkgs/tree/master
- **Package definitions**: `pkgs/by-name/` (new) or `pkgs/` (legacy) in nixpkgs
- **NixOS modules**: `nixos/modules/` in nixpkgs (e.g., `nixos/modules/services/web-servers/nginx/default.nix`)
- **NixOS tests**: `nixos/tests/` in nixpkgs (great examples of working configurations)

### Wikis & Guides
- **NixOS Wiki**: https://wiki.nixos.org/ (community-maintained, practical guides)
- **Arch Wiki**: https://wiki.archlinux.org/ (not Nix-specific but excellent for understanding Linux services/concepts)
- **Nix manual**: https://nix.dev/manual/nix/latest/
- **Nixpkgs manual**: https://nixos.org/manual/nixpkgs/stable/

## Common Nix Commands

### Building
```bash
# Build a flake output
nix build .#packages.x86_64-linux.default

# Build without creating ./result symlink
nix build .#mypackage --no-link

# Build and print store path
nix build .#mypackage --print-out-paths

# Build a NixOS system configuration
nixos-rebuild build --flake .#hostname

# Check all flake outputs
nix flake check
```

### Evaluation (fast, no building)
```bash
# Evaluate an expression
nix eval .#packages.x86_64-linux.default.name

# Show flake outputs
nix flake show

# Check flake metadata
nix flake metadata
```

### Debugging
```bash
# Interactive REPL with flake loaded
nix repl .

# In REPL: explore outputs
:lf .
outputs.packages.x86_64-linux.default

# Build with verbose output
nix build .#pkg -L

# Show derivation details
nix show-derivation .#pkg

# Show dependency tree
nix-store -q --tree $(nix build .#pkg --print-out-paths)
```

## NixOS Configuration Patterns

### Package Installation
```nix
# System-wide packages
environment.systemPackages = with pkgs; [
  vim
  git
  curl
];

# Per-user packages (Home Manager)
home.packages = with pkgs; [
  ripgrep
  fd
];
```

### Service Configuration
```nix
# Enable a service
services.nginx.enable = true;

# Service with configuration
services.nginx = {
  enable = true;
  virtualHosts."example.com" = {
    root = "/var/www/example";
    locations."/" = {
      tryFiles = "$uri $uri/ =404";
    };
  };
};
```

### Variables and Let Bindings
```nix
let
  port = 8080;
  domain = "example.com";
in {
  services.nginx.virtualHosts.${domain} = {
    listen = [{ addr = "0.0.0.0"; inherit port; }];
  };
  networking.firewall.allowedTCPPorts = [ port ];
}
```

### Conditionals
```nix
{
  config,
  lib,
  ...
}: {
  # mkIf - conditional configuration
  services.openssh = lib.mkIf config.networking.hostName == "server" {
    enable = true;
  };

  # Optional packages
  environment.systemPackages = lib.optionals config.services.xserver.enable [
    pkgs.firefox
  ];
}
```

### Overlays (Modifying Packages)
```nix
nixpkgs.overlays = [
  (final: prev: {
    myApp = prev.myApp.overrideAttrs (old: {
      patches = (old.patches or []) ++ [ ./fix.patch ];
    });
  })
];
```

### Custom Packages (stdenv.mkDerivation)
```nix
pkgs.stdenv.mkDerivation {
  pname = "my-app";
  version = "1.0.0";
  src = ./src;

  nativeBuildInputs = [ pkgs.cmake ];
  buildInputs = [ pkgs.openssl ];

  buildPhase = ''
    cmake . -DCMAKE_INSTALL_PREFIX=$out
    make
  '';

  installPhase = ''
    make install
  '';
}
```

### Writing Shell Scripts
```nix
pkgs.writeShellScriptBin "my-script" ''
  echo "Hello from Nix!"
  ${pkgs.curl}/bin/curl https://example.com
''
```

## Common Debugging Scenarios

### Infinite Recursion
**Error**: `infinite recursion encountered`
**Causes**:
- Circular module imports
- Using `config` to define `config` without `mkIf` or `mkMerge`
- Overlay referencing `final` where it should use `prev`

**Fix**: Use `lib.mkIf`, `lib.mkMerge`, or break the cycle.

### Missing Attribute
**Error**: `attribute 'foo' missing`
**Causes**:
- Package name changed in nixpkgs update
- Wrong attribute path

**Fix**: Search https://search.nixos.org/packages or `nix search nixpkgs#foo`

### Hash Mismatch (Fixed-Output Derivation)
**Error**: `hash mismatch in fixed-output derivation`
**Fix**: Use `lib.fakeHash` first, then replace with the correct hash from the error.

### Build Failure
**Debug steps**:
1. `nix build .#pkg -L` for verbose logs
2. `nix develop .#pkg` to enter the build environment
3. Run `genericBuild` phases manually: `unpackPhase`, `configurePhase`, `buildPhase`

### Evaluation Too Slow
- Use `nix eval` instead of `nix build` when you only need to check evaluation
- Use `--show-trace` to find which module is slow
- `builtins.trace` to add debug prints during evaluation
