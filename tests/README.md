# Test Infrastructure

This directory contains the test suite for the kimb-services NixOS module system.

## ⚠️ SECURITY WARNING ⚠️

**This test infrastructure contains PRIVATE KEYS that are NOT SECURE!**

- Test private keys are included directly in the repository
- These keys are used ONLY for isolated VM testing
- **NEVER use these keys in production systems**
- **NEVER copy these keys to real infrastructure**

## Test Components

### Unit Tests

The flake does not currently expose standalone unit test outputs. Quick
functional checks are embedded in the `eval-fish-functions` and
`eval-fish-syntax` flake checks instead.

### VM Integration Tests

```bash
nix build .#checks.x86_64-linux.minimal-test
nix build .#checks.x86_64-linux.network-test
nix build .#checks.x86_64-linux.working-vm-test
```

The original full end-to-end test driver (`.#tests.integrationTest.driver`)
has been retired; use the VM checks above.

### Per-Configuration Evaluation

`nix flake check` also evaluates every NixOS configuration automatically:

```bash
nix build .#checks.x86_64-linux.eval-<hostname>
```

## Test Safety

The test infrastructure is designed to be completely isolated:

- Uses separate 10.200.0.0/16 network range
- Test keys are clearly marked and separate from production
- VMs have no network access to real infrastructure  
- All test certificates use test-only domain names
- No production secrets or configuration exposed

**The test private keys are intentionally insecure for testing purposes only.**