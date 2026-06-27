#!/usr/bin/env bash

# Test runner for systems-flake flake checks

set -e

echo "=== Running systems-flake Flake Checks ==="

# Change to project root
cd "$(dirname "$0")/.."

SYSTEM="${SYSTEM:-x86_64-linux}"

echo "Running quick evaluation checks..."
nix build ".#checks.$SYSTEM.eval-fish-functions"
nix build ".#checks.$SYSTEM.eval-fish-syntax"

echo "✅ Evaluation checks passed!"

echo "Running VM integration checks..."
echo "⚠️  This may take several minutes to build VMs..."
nix build ".#checks.$SYSTEM.minimal-test"
nix build ".#checks.$SYSTEM.network-test"
nix build ".#checks.$SYSTEM.working-vm-test"

echo "✅ VM checks passed!"

echo "🎉 systems-flake test suite completed successfully!"
