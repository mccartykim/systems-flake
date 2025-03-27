{pkgs, ...}: {
  home.username = "kimb";
  home.homeDirectory = "/home/kimb";
  home.stateVersion = "23.05";

  home.packages = [
    pkgs.obsidian
    pkgs.moonlight-qt
    pkgs.legcord
    pkgs.nil
  ];

  programs.home-manager.enable = true;

  programs.tealdeer.enable = true;
  # wayland.windowManager.hyprland.enable = true;
  # wayland.windowManager.hyprland.xwayland.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  xdg.enable = true;

  programs.fish = {
    enable = true;
  };

  programs.nushell = {
    enable = true;
  };

  programs.kitty = {
    enable = true;
    themeFile = "Grass.conf";
    font = {
      package = pkgs.ibm-plex;
      name = "IBM Plex Mono";
      size = 14;
    };
  };

  programs.zoxide.enable = true;
  programs.atuin.enable = true;

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
    plugins = [
      pkgs.vimPlugins.nvim-treesitter
    ];
    extraConfig = ''
      " use <tab> to trigger completion and navigate to the next complete item
      function! CheckBackspace() abort
        let col = col('.') - 1
        return !col || getline('.')[col - 1]  =~# '\s'
      endfunction

      inoremap <silent><expr> <Tab>
            \ coc#pum#visible() ? coc#pum#next(1) :
            \ CheckBackspace() ? "\<Tab>" :
            \ coc#refresh()

      set autoindent expandtab tabstop=2 shiftwidth=2
    '';
    coc = {
      enable = true;
      settings = {
        languageserver = {
          nix = {
            command = "nil";
            filetypes = ["nix"];
            rootPatterns = ["flake.nix"];
          };
        };
      };
    };
  };
}
