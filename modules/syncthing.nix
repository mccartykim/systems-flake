# Shared syncthing service config — opt-in per host via kimb.syncthing.enable.
# All syncthing hosts use the same user/dataDir/ports; the one former per-host
# override (rich-evans guiAddress) was dropped, so the config is uniform.
# configDir is left at the nixpkgs default (dataDir/.config/syncthing).
{
  lib,
  config,
  ...
}: {
  options.kimb.syncthing.enable = lib.mkEnableOption "shared syncthing service config";

  config = lib.mkIf config.kimb.syncthing.enable {
    services.syncthing = {
      enable = true;
      openDefaultPorts = true;
      user = "kimb";
      dataDir = "/home/kimb";
    };
  };
}