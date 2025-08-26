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
- `nix eval .#tests.unitTests.testServiceIPResolution`
- `nix eval .#tests.unitTests.testEnabledServiceFiltering`

Tests core kimb-services module functionality in isolation.

### VM Integration Tests
- `nix build .#tests.integrationTest.driver -o test-driver`
- `./test-driver/bin/nixos-test-driver`

Full end-to-end testing with:
- Isolated VM network (10.200.0.0/16)
- Real Nebula certificates (test-only)
- Agenix secret encryption/decryption
- Service discovery and networking
- Cross-VM communication

### Test Network Architecture

```
Test Network: 10.200.0.0/16
├── test-lighthouse: 10.200.0.1 (simulated)
├── test-router:     10.200.0.50 (reverse-proxy, blog)
├── test-server:     10.200.0.40 (homeassistant, copyparty)  
└── test-desktop:    10.200.0.10 (no services)
```

### Test Secrets

All test secrets are encrypted with agenix:
- `secrets/test-nebula-*-cert.age` - Nebula certificates
- `secrets/test-nebula-*-key.age` - Nebula private keys  
- `secrets/test-ssh-*-key.age` - SSH private keys for orchestration

**Test VMs can decrypt their own secrets using embedded private keys.**

## What Gets Tested

✅ **Functional Programming Patterns**
- Services use `lib.mapAttrs`, `lib.filterAttrs` instead of hardcoded references
- Dynamic service configuration generation
- IP resolution from registry works correctly

✅ **Service Registry**
- `cfg.computed.servicesWithIPs` provides host IPs
- Service filtering by traits (enabled, public, auth type)
- Cross-host service discovery

✅ **Secret Management**
- Agenix encryption/decryption works in VMs
- Private keys properly embedded for testing
- Secrets accessible to services that need them

✅ **Network Architecture**
- VM-to-VM communication
- Service proxy configuration
- DNS resolution for test domains

## Running Tests

```bash
# Quick unit tests
nix eval .#tests.unitTests.testServiceIPResolution --json
nix eval .#tests.unitTests.testEnabledServiceFiltering --json

# Full integration test (takes ~5-10 minutes)
nix build .#tests.integrationTest.driver -o test-driver
./test-driver/bin/nixos-test-driver

# Or use the test runner script
./tests/run-tests.sh
```

## Test Safety

The test infrastructure is designed to be completely isolated:

- Uses separate 10.200.0.0/16 network range
- Test keys are clearly marked and separate from production
- VMs have no network access to real infrastructure  
- All test certificates use test-only domain names
- No production secrets or configuration exposed

**The test private keys are intentionally insecure for testing purposes only.**