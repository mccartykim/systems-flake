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
      default = true;
      description = "Enable zellij terminal multiplexer";
    };

    tmux = mkOption {
      type = types.bool;
      default = false;
      description = "Enable tmux terminal multiplexer";
    };
  };

  config = mkIf config.modules.terminal-enhanced.enable {
    programs.fzf.enable = config.modules.terminal-enhanced.fzf;
    programs.eza.enable = config.modules.terminal-enhanced.eza;
    programs.zellij.enable = config.modules.terminal-enhanced.zellij;

    programs.tmux = mkIf config.modules.terminal-enhanced.tmux {
      enable = true;
      mouse = true;
      keyMode = "vi";
    };

    programs.kitty = mkIf config.modules.terminal-enhanced.kitty {
      enable = true;
      environment = {
        "PAGER" = ":builtin";
      };
    };

    home.packages = with pkgs; (optional config.modules.terminal-enhanced.tealdeer tealdeer);
  };
}
