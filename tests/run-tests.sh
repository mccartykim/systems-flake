#!/usr/bin/env bash

# Test runner for kimb-services integration tests

set -e

echo "=== Running kimb-services Integration Tests ==="

# Change to project root
cd "$(dirname "$0")/.."

# Run unit tests
echo "Running unit tests..."
nix eval --json .#tests.unitTests.testServiceIPResolution
nix eval --json .#tests.unitTests.testEnabledServiceFiltering

echo "✅ Unit tests passed!"

# Run VM integration test
echo "Running VM integration test..."
echo "⚠️  This may take several minutes to build VMs..."

nix build .#tests.integrationTest.driver -o test-driver

echo "🚀 Starting VM integration test..."
./test-driver/bin/nixos-test-driver

echo "✅ All tests passed successfully!"

# Cleanup
echo "Cleaning up test artifacts..."
rm -f test-driver
rm -rf test-tmp/

echo "🎉 kimb-services test suite completed successfully!"