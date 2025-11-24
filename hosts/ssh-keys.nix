# Centralized SSH public keys registry
# Named attributes that can be converted to lists as needed
let
  # User keys (personal devices) - for SSH access to hosts
  userKeys = {
    main = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZ+5yePKB5vKsm5MJg6SOZSwO0GCV9UBw5cmGx7NmEg mccartykim@zoho.com";
    historian = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN2bgYbsq7Hp5RoM1Dlt59CdGEjvV6CoCi75pR4JiG5e mccartykim@zoho.com";
    total-eclipse = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJY8TB1PRV5e8e8QgdwFRPbuRIzjeS1oFY1WOUKTYnrj mccartykim@zoho.com";
    cheesecake = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQgFzMg37QTeFE2ybQRHfVEQwW/Wz7lK6jPPmctFd/U kimb@surface3go";
    marshmallow = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICwE1JLDrS+C2GcUcFb8ZvDRJX0lF+e0CLhJhFK8DpTO mccartykim@zoho.com";
  };

  # Host keys (SSH host keys for machine identity / agenix)
  # Desktops & laptops - user-facing machines
  desktopHostKeys = {
    historian = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBXpuMSA1RXsYs6cEhvNqzhWpbIe2NB0ya1MUte87SD+";
    total-eclipse = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII25uGB19xLNzpzOFKUHp93EtNPxHXgeKotRDsdqdWa7";
    marshmallow = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILlKSgkr7eXGq9Lcg/5TfH9eudHLEP1q4zAvA8zhq9wh";
    bartleby = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGCZ/lfNz+FcRNwbRMeT658YOH0YdCgLRBn/bcegj7pi";
  };

  # Servers & appliances - network infrastructure
  applianceHostKeys = {
    maitred = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXJ4JeYtJiV8ltScewAu+N8KYLy+muo+mP07XznOzjX";
    rich-evans = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOCXEs7zN0NNdWyZ9MJ4pI0R8RAPH6EFj3E2Qp2Xzc1k";
    arbus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcAHg30CQV01JYsRlyhNbh0Noyo1iPnde9nqDtV5SJY";
  };

  # Bootstrap key for agenix re-encryption
  bootstrap = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQgFzMg37QTeFE2ybQRHfVEQwW/Wz7lK6jPPmctFd/U";
in {
  # Named attributes for selective access
  user = userKeys;
  desktop = desktopHostKeys;
  appliance = applianceHostKeys;
  inherit bootstrap;

  # All host keys combined (for agenix)
  host = desktopHostKeys // applianceHostKeys;

  # Lists
  userList = builtins.attrValues userKeys;
  desktopList = builtins.attrValues desktopHostKeys;
  applianceList = builtins.attrValues applianceHostKeys;

  # For SSH authorized_keys - only user keys from desktops/laptops
  # (appliances like arbus don't need to SSH into other machines)
  authorizedKeys = builtins.attrValues userKeys;

  # For agenix
  agenixHosts = desktopHostKeys // applianceHostKeys;
}
