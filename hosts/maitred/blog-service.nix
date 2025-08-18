# Blog service container configuration for maitred
# Runs just the mist-blog service in isolation
{ config, pkgs, inputs, ... }:

{
  # NixOS container for the blog service
  containers.blog-service = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "192.168.100.1";      # Router's container bridge IP  
    localAddress = "192.168.100.3";     # Blog service container IP (no internet access needed)
    
    config = { config, pkgs, ... }: {
      # Mist blog service
      systemd.services.mist-blog = {
        description = "Mist Blog Service";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${inputs.mist-blog.packages.${pkgs.system}.default}/bin/mist_blog";
          Restart = "always";
          Type = "simple";
          DynamicUser = true;
          Environment = [ 
            "PORT=8080"
            "MIST_HOST=0.0.0.0"  # Try Mist-specific variable
            "HOST=0.0.0.0"       # Keep generic one too
          ];
        };
      };
      
      # Open firewall for blog service
      networking.firewall.allowedTCPPorts = [ 8080 ];
      
      # Minimal system packages
      environment.systemPackages = with pkgs; [
        curl
        htop
      ];
      
      system.stateVersion = "24.11";
    };
  };
}