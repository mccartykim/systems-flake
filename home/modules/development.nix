{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.modules.development = {
    enable = mkEnableOption "development tools and configurations";

    jujutsu = {
      email = mkOption {
        type = types.str;
        default = "kimb@kimb.dev";
        description = "Email for jujutsu commits";
      };

      name = mkOption {
        type = types.str;
        default = "Kimberly McCarty";
        description = "Name for jujutsu commits";
      };
    };
  };

  config = mkIf config.modules.development.enable {
    programs = {
      git.enable = true;

      jujutsu = {
        enable = true;
        settings = {
          user = {
            inherit (config.modules.development.jujutsu) email name;
          };
          ui.diff-formatter = [
            "${pkgs.difftastic}/bin/difft"
            "--color=always"
            "$left"
            "$right"
          ];
        };
      };

      zed-editor = {
        enable = true;
        extensions = [
          "xy-zed"
          "nix"
          "gleam"
        ];
      };
    };

    home.packages = with pkgs; [
      nil
      nh
      meld
      emacs
      ripgrep
      coreutils
      fd
      clang
    ];
  };
}
