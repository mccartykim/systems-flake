{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.modules.shell-essentials = {
    enable = mkEnableOption "essential shell tools and configurations";
  };

  config = mkIf config.modules.shell-essentials.enable {
    programs = {
      fish.enable = true;
      zoxide.enable = true;
      atuin.enable = true;

      direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    };
  };
}
