# Example: Simple Nebula setup without age (for testing)
# Copy certificates manually to /etc/nebula/
{config, ...}: 
let
  registry = import ../hosts/nebula-registry.nix;
in {
  imports = [../modules/nebula-mesh.nix];

  services.nebula-mesh = {
    enable = true;
    inherit (config.networking) hostName;
    hostIP = "10.100.0.X"; # Choose unused IP and add to network-ips.nix
    groups = ["nixos"];

    # Point to lighthouse
    lighthouses = [
      {
        meshIP = registry.network.lighthouse.ip;
        publicEndpoints = [registry.network.lighthouse.external];
      }
    ];
  };

  # Manually copy certificates
  systemd.tmpfiles.rules = [
    "d /etc/nebula 0755 nebula-mesh nebula-mesh -"
  ];
}
