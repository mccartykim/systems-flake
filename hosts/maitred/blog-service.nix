# Blog service container
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.kimb;
  blogService = cfg.services.blog;
  # Host-side veth IP for this container; also the address blog-service uses
  # for DNS (unbound on maitred listens on all interfaces).
  hostVeth = "192.168.100.11";
in {
  containers.blog-service = lib.mkIf blogService.enable {
    autoStart = true;
    privateNetwork = true;
    # Each container needs unique hostAddress for point-to-point veth link.
    # Using .11 to avoid collision with reverse-proxy which uses containerBridge (.1).
    hostAddress = hostVeth;
    localAddress = blogService.containerIP;

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # Resolve DNS through unbound on maitred via the host-side veth IP.
      # Same NSS-bypass pattern as reverse-proxy — see note there for why nscd
      # and nssModules are forced off alongside the static resolv.conf.
      networking.nameservers = [hostVeth];
      services.nscd.enable = false;
      system.nssModules = lib.mkForce [];
      networking.resolvconf.enable = false;
      environment.etc."resolv.conf".text = ''
        nameserver ${hostVeth}
      '';

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
