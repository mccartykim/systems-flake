# Blog service container using kimb-services options
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.kimb;
  blogService = cfg.services.blog;
in {
  # Blog service container (uses mist-blog flake input)
  containers.blog-service = lib.mkIf blogService.enable {
    autoStart = true;
    privateNetwork = true;
    hostAddress = cfg.networks.containerBridge;
    localAddress = blogService.containerIP;

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      networking.nameservers = [cfg.networks.containerBridge];

      environment.systemPackages = [inputs.mist-blog.packages.x86_64-linux.default];

      systemd.services.mist-blog = {
        description = "Mist Blog Service";
        after = ["network.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = "${inputs.mist-blog.packages.x86_64-linux.default}/bin/mist_blog";
          Restart = "always";
          User = "nobody";
          WorkingDirectory = "/tmp";
        };
      };

      networking.firewall.allowedTCPPorts = [blogService.port];
      system.stateVersion = "24.11";
    };
  };
}
