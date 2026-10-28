# Blog service container — the a3j.8.2 migration from maitred.
#
# Same nspawn-container shape as maitred's blog-service (the mist-blog module
# uses `self.packages`, which is scoped inside the container's module args —
# keeping it a container avoids polluting historian's `self`). The content is
# the git-tracked kimb-blog-content input, so there is NO runtime state to move.
#
# Network: a historian-local point-to-point veth (192.168.102.1 <-> .3), the
# same no-bridge pattern maitred uses with 192.168.100.x. Historian's Caddy
# (host service) reaches it at the container IP (see reverse-proxy.nix).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.kimb;
  blogService = cfg.services.blog;
  # Host-side veth IP for this container; also the container's DNS resolver.
  hostVeth = "192.168.102.1";
in {
  containers.blog-service = lib.mkIf blogService.enable {
    autoStart = true;
    privateNetwork = true;
    hostAddress = hostVeth;
    localAddress = blogService.containerIP;

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # Resolve DNS via the host-side veth IP (historian runs no local
      # resolver on that veth, so point at maitred's unbound over the LAN).
      networking.nameservers = ["192.168.69.1"];
      services.nscd.enable = false;
      system.nssModules = lib.mkForce [];
      networking.resolvconf.enable = false;
      environment.etc."resolv.conf".text = ''
        nameserver 192.168.69.1
      '';

      imports = [inputs.mist-blog.nixosModules.default];
      _module.args.self = inputs.mist-blog;
      environment.systemPackages = [inputs.mist-blog.packages.x86_64-linux.default];

      services.mist-blog = {
        enable = true;
        contentDir = "${inputs.kimb-blog-content}/content";
        port = blogService.port;
        host = "0.0.0.0";
        title = "kimb.dev";
        description = "The personal blog of Kimberly McCarty";
        author = "Kimberly McCarty";
        email = "mccartykim@zoho.com";
        baseUrl = "https://kimb.dev";
        copyright = "Kimberly McCarthy (CC BY 4.0)";
      };

      networking.firewall.allowedTCPPorts = [blogService.port];
      system.stateVersion = "24.11";
    };
  };
}
