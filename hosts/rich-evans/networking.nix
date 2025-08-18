# Static networking configuration for rich-evans
{ config, lib, pkgs, ... }:

{
  networking = {
    # Keep DHCP as fallback initially
    useDHCP = false;
    
    interfaces.eno1 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "192.168.68.200";  # Static IP in high range to avoid DHCP
        prefixLength = 24;
      }];
    };
    
    defaultGateway = {
      address = "192.168.68.1";
      interface = "eno1";
    };
    nameservers = [ 
      "1.1.1.1"  # Cloudflare for now
      "1.0.0.1"  # Will become self once DNS is running
    ];
  };
  
  # Fallback: if static IP fails, you can still connect via Nebula
  # at 10.100.0.40 or Tailscale to fix it
}