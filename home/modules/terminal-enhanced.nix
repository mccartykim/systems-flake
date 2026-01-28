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
        extraConfig = ''
          # Per-host color theming
          # Historian: soft light blue-green theme
          if-shell 'test "$(hostname)" = "historian"' \
            'set -g status-style "bg=#E0F7FA,fg=#006064"; \
             set -g window-status-current-style "bg=#81C784,fg=#1B5E20"; \
             set -g pane-border-style "fg=#80CBC4"; \
             set -g pane-active-border-style "fg=#00897B"'

          # Total-Eclipse: dark purple theme
          if-shell 'test "$(hostname)" = "total-eclipse"' \
            'set -g status-style "bg=#4A148C,fg=#E1BEE7"; \
             set -g window-status-current-style "bg=#7B1FA2,fg=#F3E5F5"; \
             set -g pane-border-style "fg=#6A1B9A"; \
             set -g pane-active-border-style "fg=#9C27B0"'

          # Marshmallow: soft pink theme
          if-shell 'test "$(hostname)" = "marshmallow"' \
            'set -g status-style "bg=#F48FB1,fg=#880E4F"; \
             set -g window-status-current-style "bg=#EC407A,fg=#FCE4EC"; \
             set -g pane-border-style "fg=#F06292"; \
             set -g pane-active-border-style "fg=#E91E63"'
        '';
      };

      kitty = mkIf config.modules.terminal-enhanced.kitty {
        enable = true;
        environment = {
          "PAGER" = ":builtin";
        };
      };
    };

    home.packages = with pkgs; (optional config.modules.terminal-enhanced.tealdeer tealdeer);
  };
}
