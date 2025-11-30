{pkgs, ...}: {
  imports = [
    ./modules/shell-essentials.nix
    ./modules/development.nix
    ./modules/terminal-enhanced.nix
  ];

  home = {
    username = "kimb";
    homeDirectory = "/home/kimb";
    stateVersion = "23.05";

    # Bartleby-specific packages
    packages = [
      pkgs.obsidian
      pkgs.moonlight-qt
      pkgs.legcord
    ];
  };

  # Enable modules
  modules = {
    shell-essentials.enable = true;
    development.enable = true;
    terminal-enhanced = {
      enable = true;
      kitty = true;
      tealdeer = true;
    };
  };

  xdg.enable = true;

  # Programs configuration
  programs = {
    home-manager.enable = true;

    # Additional shell for bartleby
    nushell.enable = true;

    # Bartleby-specific kitty config
    kitty = {
      themeFile = "Grass";
      font = {
        package = pkgs.ibm-plex;
        name = "IBM Plex Mono";
        size = 14;
      };
    };

    neovim = {
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
  };
}
