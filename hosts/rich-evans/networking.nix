# Networking configuration for rich-evans
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Networking configuration
  networking = {
    # Disable NetworkManager on this server - use systemd-networkd instead
    networkmanager.enable = lib.mkForce false;

    # Use systemd-networkd for server networking
    useNetworkd = true;

    useDHCP = false; # Managed by systemd-networkd

    # Note: If you want a static IP later, you can:
    # 1. Set a DHCP reservation on maitred based on MAC address
    # 2. Or configure a static IP matching the current subnet
  };

  systemd.network.enable = true;

  # Configure eno1 interface with DHCP via systemd-networkd
  systemd.network.networks."10-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig = {
      DHCP = "yes";
      # Get IP from maitred's DHCP pool (192.168.69.100-199)
    };
    linkConfig.RequiredForOnline = "routable";
  };

  # Access via:
  # - Nebula: 10.100.0.40 (always works)
  # - Tailscale: backup access
  # - rich-evans.local: mDNS discovery
}
