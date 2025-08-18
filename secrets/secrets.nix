# Agenix secrets configuration
# This file defines which systems can decrypt which secrets
let
  # Import node registry for centralized management
  registry = import ../hosts/nebula-registry.nix;
  
  # Extract public keys from registry (filter out nodes without keys)
  nodesWithKeys = builtins.filter (node: node.publicKey != null) 
    (builtins.attrValues registry.nodes);
  allSystems = map (node: node.publicKey) nodesWithKeys;
in
{
  # Shared CA certificate - all systems can decrypt
  "nebula-ca.age".publicKeys = allSystems;
  
  # Individual certificates - only the specific system can decrypt
  # Generated dynamically from registry
} // (
  let
    # Create cert/key entries for each node with a public key
    createNodeSecrets = nodeName: node:
      if node.publicKey != null then {
        "nebula-${nodeName}-cert.age".publicKeys = [ node.publicKey ];
        "nebula-${nodeName}-key.age".publicKeys = [ node.publicKey ];
      } else {};
  in
    builtins.foldl' (acc: entry: acc // entry) {} 
      (builtins.attrValues (builtins.mapAttrs createNodeSecrets registry.nodes))
}