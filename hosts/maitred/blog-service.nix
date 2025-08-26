# Blog service container using kimb-services options
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.kimb;

in {
  # Blog service container (uses mist-blog flake input)
  containers.blog-service = lib.mkIf cfg.services.blog.enable {
    autoStart = true;
    privateNetwork = true;
    hostAddress = cfg.networks.containerBridge;
    localAddress = "192.168.100.3";

    config = { config, pkgs, ... }: {
      environment.systemPackages = [ inputs.mist-blog.packages.x86_64-linux.default ];
      
      systemd.services.mist-blog = {
        description = "Mist Blog Service";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${inputs.mist-blog.packages.x86_64-linux.default}/bin/mist-blog";
          Restart = "always";
          User = "nobody";
          WorkingDirectory = "/tmp";
        };
      };

      networking.firewall.allowedTCPPorts = [ cfg.services.blog.port ];
      system.stateVersion = "24.11";
    };
  };
}