# Blog and Caddy configuration for maitred
{ config, pkgs, inputs, ... }:

{
  # Define the mist-blog service directly
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
      Environment = [ "PORT=8080" ];
    };
  };
  
  # Caddy reverse proxy for HTTPS and serving the blog
  services.caddy = {
    enable = true;
    virtualHosts = {
      # Production domain with HTTPS
      "kimb.dev" = {
        extraConfig = ''
          reverse_proxy localhost:8080
        '';
      };
      
      # Local access via hostname
      "maitred.local" = {
        extraConfig = ''
          reverse_proxy localhost:8080
        '';
      };
      
      # Access via Tailscale hostname
      "maitred" = {
        extraConfig = ''
          reverse_proxy localhost:8080
        '';
      };
      
      # Access via Nebula IP
      "10.100.0.1" = {
        extraConfig = ''
          reverse_proxy localhost:8080
        '';
      };
      
      # Direct HTTP access on port 80
      ":80" = {
        extraConfig = ''
          reverse_proxy localhost:8080
        '';
      };
    };
  };
  
  # Open firewall for HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}