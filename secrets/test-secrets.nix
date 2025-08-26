# Test secrets configuration for VM integration tests
# These are test-only secrets that can include private keys since they're not real
let
  # Read test SSH public keys
  testRouterKey = builtins.readFile ../tests/test-keys/test-ssh/test-router.pub;
  testServerKey = builtins.readFile ../tests/test-keys/test-ssh/test-server.pub;
  testDesktopKey = builtins.readFile ../tests/test-keys/test-ssh/test-desktop.pub;
  
  # All test systems can decrypt all test secrets (simplified for testing)
  allTestSystems = [ testRouterKey testServerKey testDesktopKey ];
in {
  # Test Nebula CA certificate and key (shared by all test systems)
  "test-nebula-ca-cert.age".publicKeys = allTestSystems;
  "test-nebula-ca-key.age".publicKeys = allTestSystems;
  
  # Test Nebula host certificates and keys
  "test-nebula-router-cert.age".publicKeys = allTestSystems;
  "test-nebula-router-key.age".publicKeys = allTestSystems;
  "test-nebula-server-cert.age".publicKeys = allTestSystems;
  "test-nebula-server-key.age".publicKeys = allTestSystems;
  "test-nebula-desktop-cert.age".publicKeys = allTestSystems;
  "test-nebula-desktop-key.age".publicKeys = allTestSystems;
  
  # Test SSH keys (private keys for VM access)
  "test-ssh-router-key.age".publicKeys = allTestSystems;
  "test-ssh-server-key.age".publicKeys = allTestSystems;
  "test-ssh-desktop-key.age".publicKeys = allTestSystems;
}