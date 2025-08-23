# Single source of truth for all network IPs
# This file defines all static IP assignments for the network
{
  # Nebula mesh network (10.100.0.0/16)
  nebula = {
    subnet = "10.100.0.0/16";
    
    # Lighthouse (Google Cloud)
    lighthouse = {
      ip = "10.100.0.1";
      external = "35.222.40.201:4242";
    };
    
    # NixOS hosts
    hosts = {
      # Servers
      rich-evans = "10.100.0.40";
      
      # Router
      maitred = "10.100.0.50";
      
      # Desktops
      historian = "10.100.0.10";
      total-eclipse = "10.100.0.6";
      
      # Laptops
      marshmallow = "10.100.0.4";
      bartleby = "10.100.0.3";
    };
  };
  
  # Local network (192.168.69.0/24)
  lan = {
    subnet = "192.168.69.0/24";
    gateway = "192.168.69.1";
    
    # DHCP range: .100-.199
    dhcp = {
      start = "192.168.69.100";
      end = "192.168.69.199";
    };
    
    # Static assignments
    static = {
      maitred = "192.168.69.1";
      rich-evans = "192.168.68.200";  # Note: different subnet when at old location
      # Add other static LAN IPs as needed
    };
  };
  
  # Container network (192.168.100.0/24)
  containers = {
    subnet = "192.168.100.0/24";
    
    # maitred container bridge
    bridge = "192.168.100.1";
    
    # Container IPs
    hosts = {
      reverse-proxy = "192.168.100.2";
      blog-service = "192.168.100.3";
      authelia = "192.168.100.4";
    };
  };
  
  # Tailscale backup network (100.64.0.0/10)
  tailscale = {
    subnet = "100.64.0.0/10";
    # Tailscale IPs are dynamically assigned
  };
}