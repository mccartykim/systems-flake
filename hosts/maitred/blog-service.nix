# Blog service container using kimb-services options
# Now with containernet mesh integration for host-decoupled networking
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
    # Each container needs unique hostAddress for point-to-point veth link
    # Using .11 to avoid collision with reverse-proxy which uses containerBridge (.1)
    hostAddress = "192.168.100.11";
    localAddress = blogService.containerIP;

    # Allow tun device for nebula containernet
    allowedDevices = [
      {node = "/dev/net/tun"; modifier = "rw";}
    ];

    # Bind-mount cert-service token for containernet integration
    bindMounts."/run/containernet/token" = {
      hostPath = "/etc/ephemeral-ca/token";
      isReadOnly = true;
    };

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # Import containernet module for fire-and-forget mesh integration
      imports = [../../modules/containernet-container.nix];

      # Enable containernet with blog port exposed
      kimb.containernet = {
        enable = true;
        hostAddress = "192.168.100.11";  # Must match container's hostAddress
        servicePorts = [blogService.port];
      };

      # DNS via containerBridge (host runs DNS forwarder)
      networking.nameservers = ["192.168.100.1"];

      environment.systemPackages = [inputs.mist-blog.packages.x86_64-linux.default];

      systemd.services.mist-blog = {
        description = "Mist Blog Service";
        after = ["network.target" "nebula-containernet.service"];
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
