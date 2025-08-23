# Age-encrypted Nebula secrets management
# This file defines which machines get which Nebula certificates
{
  # Lighthouse configuration - manually deployed
  lighthouse = {
    hostIP = "10.100.0.1";
    externalIP = "35.222.40.201";
    secrets = [
      "ca.crt"
      "lighthouse.crt"
      "lighthouse.key"
    ];
  };

  # NixOS machines with automatic certificate deployment
  nodes = {
    historian = {
      hostIP = "10.100.0.10";
      groups = ["laptops" "nixos"];
      secrets = [
        "ca.crt"
        "historian.crt"
        "historian.key"
      ];
    };

    marshmallow = {
      hostIP = "10.100.0.4";  # Fixed: was incorrect 10.100.0.20
      groups = ["laptops" "nixos"];
      secrets = [
        "ca.crt"
        "marshmallow.crt"
        "marshmallow.key"
      ];
    };

    bartleby = {
      hostIP = "10.100.0.3";  # Fixed: was incorrect 10.100.0.30
      groups = ["laptops" "nixos"];
      secrets = [
        "ca.crt"
        "bartleby.crt"
        "bartleby.key"
      ];
    };

    rich-evans = {
      hostIP = "10.100.0.40";
      groups = ["servers" "nixos"];
      secrets = [
        "ca.crt"
        "rich-evans.crt"
        "rich-evans.key"
      ];
    };
  };

  # Lighthouse endpoints for all nodes
  lighthouses = [
    {
      meshIP = "10.100.0.1";
      publicEndpoints = ["35.222.40.201:4242"];
    }
  ];
}
