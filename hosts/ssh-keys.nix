# SSH Keys Registry
# Derives host keys from nebula-registry.nix, adds user keys
let
  registry = import ./nebula-registry.nix;

  # User keys (personal SSH keys for authorized_keys)
  userKeys = {
    main = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZ+5yePKB5vKsm5MJg6SOZSwO0GCV9UBw5cmGx7NmEg mccartykim@zoho.com";
    historian = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN2bgYbsq7Hp5RoM1Dlt59CdGEjvV6CoCi75pR4JiG5e mccartykim@zoho.com";
    total-eclipse = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJY8TB1PRV5e8e8QgdwFRPbuRIzjeS1oFY1WOUKTYnrj mccartykim@zoho.com";
    cheesecake = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQgFzMg37QTeFE2ybQRHfVEQwW/Wz7lK6jPPmctFd/U kimb@surface3go";
    marshmallow = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICwE1JLDrS+C2GcUcFb8ZvDRJX0lF+e0CLhJhFK8DpTO mccartykim@zoho.com";
  };

  # Desktop host keys (derived from registry)
  desktopHostKeys = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = registry.nodes.${name}.publicKey;
    })
    registry.desktops
  );

  # Laptop host keys (derived from registry)
  laptopHostKeys = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = registry.nodes.${name}.publicKey;
    })
    registry.laptops
  );

  # Server/appliance host keys (derived from registry)
  applianceHostKeys = builtins.listToAttrs (
    builtins.filter (x: x.value != null) (
      map (name: {
        inherit name;
        value = registry.nodes.${name}.publicKey or null;
      })
        (builtins.attrNames (builtins.removeAttrs registry.nodes (registry.desktops ++ registry.laptops ++ ["lighthouse"])))
    )
  );
in {
  # Named attributes for selective access
  user = userKeys;
  desktop = desktopHostKeys;
  laptop = laptopHostKeys;
  appliance = applianceHostKeys;

  # Bootstrap key for agenix re-encryption
  inherit (registry) bootstrap;

  # All host keys combined (for agenix)
  host = registry.hostKeys;

  # Lists
  userList = builtins.attrValues userKeys;
  desktopList = builtins.attrValues desktopHostKeys;
  laptopList = builtins.attrValues laptopHostKeys;
  applianceList = builtins.attrValues applianceHostKeys;

  # For SSH authorized_keys - user keys from personal devices
  authorizedKeys = builtins.attrValues userKeys;

  # For agenix - all host keys
  agenixHosts = registry.hostKeys;
}
