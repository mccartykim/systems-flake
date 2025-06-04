{pkgs, ...}: {
  imports = [
    ./modules/shell-essentials.nix
    ./modules/development.nix
    ./modules/terminal-enhanced.nix
  ];

  home.username = "kimb";
  home.homeDirectory = "/home/kimb";
  home.stateVersion = "23.05";

  # Enable modules
  modules.shell-essentials.enable = true;
  modules.development.enable = true;
  modules.terminal-enhanced = {
    enable = true;
    kitty = true;
    tealdeer = true;
  };

  # Bartleby-specific packages
  home.packages = [
    pkgs.obsidian
    pkgs.moonlight-qt
    pkgs.legcord
  ];

  programs.home-manager.enable = true;
  xdg.enable = true;

  # Additional shell for bartleby
  programs.nushell.enable = true;

  # Bartleby-specific kitty config
  programs.kitty = {
    themeFile = "Grass.conf";
    font = {
      package = pkgs.ibm-plex;
      name = "IBM Plex Mono";
      size = 14;
    };
  };

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
