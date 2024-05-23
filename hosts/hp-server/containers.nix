{pkgs, ...}: {
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-+" ];
    externalInterface = "eno1";
  };
  containers.transmission = {
    privateNetwork = true;
    config = {config, pkgs, lib, ...}: {
      services.tailscale = {
        enable = true;
      };
    };
  };
}
