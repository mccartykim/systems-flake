# Example: Simple Nebula setup without age (for testing)
# Copy certificates manually to /etc/nebula/
{config, ...}: {
  imports = [../modules/nebula-mesh.nix];

  services.nebula-mesh = {
    enable = true;
    inherit (config.networking) hostName;
    hostIP = "10.100.0.50"; # Pick an unused IP
    groups = ["nixos"];

    # Point to lighthouse
    lighthouses = [
      {
        meshIP = "10.100.0.1";
        publicEndpoints = ["35.222.40.201:4242"];
      }
    ];
  };

  # Manually copy certificates
  systemd.tmpfiles.rules = [
    "d /etc/nebula 0755 nebula-mesh nebula-mesh -"
  ];
}
