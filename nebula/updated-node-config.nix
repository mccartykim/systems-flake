# Updated NixOS node configuration pointing to your lighthouse
{ config, pkgs, ... }:

{
  services.nebula.networks.mesh = {
    enable = true;
    isLighthouse = false;
    
    # Certificates
    ca = "/etc/nebula/ca.crt";
    cert = "/etc/nebula/HOSTNAME.crt";  # Replace HOSTNAME with your machine name
    key = "/etc/nebula/HOSTNAME.key";   # Replace HOSTNAME with your machine name
    
    # Point to your lighthouse at Google Cloud
    lighthouses = [ "10.100.0.1" ];
    staticHostMap = {
      "10.100.0.1" = [ "35.222.40.201:4242" ];
    };
    
    # Additional settings
    settings = {
      punchy = {
        punch = true;
      };
      
      relay = {
        relays = [ "10.100.0.1" ];
        am_relay = false;
        use_relays = true;
      };
      
      tun = {
        disabled = false;
        dev = "nebula1";
      };
      
      logging = {
        level = "info";
      };
    };
    
    # Firewall rules
    firewall = {
      outbound = [{
        port = "any";
        proto = "any";
        host = "any";
      }];
      
      inbound = [
        {
          port = "any";
          proto = "icmp";
          host = "any";
        }
        {
          port = 22;
          proto = "tcp";
          host = "any";
        }
      ];
    };
  };
  
  # Open firewall for Nebula
  networking.firewall.allowedUDPPorts = [ 4242 ];
}