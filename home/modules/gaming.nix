{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.modules.gaming = {
    enable = mkEnableOption "gaming-related packages and configurations";

    steam = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Steam";
    };

    umu = mkOption {
      type = types.bool;
      default = true;
      description = "Enable umu-launcher";
    };
  };

  config = mkIf config.modules.gaming.enable {
    home.packages = with pkgs;
      (optional config.modules.gaming.steam steam)
      ++ (optional config.modules.gaming.umu umu-launcher);
  };
}
