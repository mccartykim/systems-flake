{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.modules.terminal-enhanced = {
    enable = mkEnableOption "enhanced terminal tools and utilities";

    fzf = mkOption {
      type = types.bool;
      default = true;
      description = "Enable fzf fuzzy finder";
    };

    eza = mkOption {
      type = types.bool;
      default = true;
      description = "Enable eza (modern ls replacement)";
    };

    tealdeer = mkOption {
      type = types.bool;
      default = true;
      description = "Enable tealdeer (tldr client)";
    };

    kitty = mkOption {
      type = types.bool;
      default = false;
      description = "Enable kitty terminal";
    };

    zellij = mkOption {
      type = types.bool;
      default = false;
      description = "Enable zellij terminal multiplexer";
    };

    tmux = mkOption {
      type = types.bool;
      default = true;
      description = "Enable tmux terminal multiplexer";
    };
  };

  config = mkIf config.modules.terminal-enhanced.enable {
    programs = {
      fzf.enable = config.modules.terminal-enhanced.fzf;
      eza.enable = config.modules.terminal-enhanced.eza;
      zellij.enable = config.modules.terminal-enhanced.zellij;

      tmux = mkIf config.modules.terminal-enhanced.tmux {
        enable = true;
        mouse = true;
        keyMode = "vi";
        extraConfig = "";
      };

      kitty = mkIf config.modules.terminal-enhanced.kitty {
        enable = true;
        environment = {
          "PAGER" = ":builtin";
        };
        # kitty #10102: __watch_conf__ recursively inotify-watches the parent
        # dir of kitty.conf. Under home-manager that dir is inside /nix/store,
        # so it walks the WHOLE store (~500k watches) and exhausts the system
        # inotify pool. Live reload is already broken on NixOS anyway, so
        # disable the watcher. Drop when kitty ships the non-recursive fix
        # past 0.47.1.
        settings.auto_reload_config = "no";
      };
    };

    home.packages = with pkgs; (optional config.modules.terminal-enhanced.tealdeer tealdeer);
  };
}
