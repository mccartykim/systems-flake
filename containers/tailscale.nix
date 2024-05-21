{ pkgs, config, ... }: {
  containers.tailscale = {
    config = {
      services.tailscale.enable = true;
    };
  };
}
