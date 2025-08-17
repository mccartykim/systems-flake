# Agenix secrets configuration
# This file defines which systems can decrypt which secrets
let
  # System SSH public keys (from /etc/ssh/ssh_host_ed25519_key.pub)
  historian = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBXpuMSA1RXsYs6cEhvNqzhWpbIe2NB0ya1MUte87SD+";
  marshmallow = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILlKSgkr7eXGq9Lcg/5TfH9eudHLEP1q4zAvA8zhq9wh";
  bartleby = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGCZ/lfNz+FcRNwbRMeT658YOH0YdCgLRBn/bcegj7pi";
  rich-evans = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOCXEs7zN0NNdWyZ9MJ4pI0R8RAPH6EFj3E2Qp2Xzc1k";
  total-eclipse = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII25uGB19xLNzpzOFKUHp93EtNPxHXgeKotRDsdqdWa7";
  
  # All systems that need the CA cert
  allSystems = [ historian marshmallow bartleby rich-evans total-eclipse ];
in
{
  # Shared CA certificate - all systems can decrypt
  "nebula-ca.age".publicKeys = allSystems;
  
  # Individual certificates - only the specific system can decrypt
  "nebula-historian-cert.age".publicKeys = [ historian ];
  "nebula-historian-key.age".publicKeys = [ historian ];
  
  "nebula-marshmallow-cert.age".publicKeys = [ marshmallow ];
  "nebula-marshmallow-key.age".publicKeys = [ marshmallow ];
  
  "nebula-bartleby-cert.age".publicKeys = [ bartleby ];
  "nebula-bartleby-key.age".publicKeys = [ bartleby ];
  
  "nebula-rich-evans-cert.age".publicKeys = [ rich-evans ];
  "nebula-rich-evans-key.age".publicKeys = [ rich-evans ];
  
  "nebula-total-eclipse-cert.age".publicKeys = [ total-eclipse ];
  "nebula-total-eclipse-key.age".publicKeys = [ total-eclipse ];
}