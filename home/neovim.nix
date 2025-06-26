{
  pkgs,
  home-manager,
  ...
}: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;

    plugins = with pkgs.vimPlugins; [
      oil-nvim
      nvim-treesitter
      nvim-treesitter-parsers.nix
      nvim-treesitter-parsers.html
      nvim-treesitter-parsers.markdown
      nvim-treesitter-parsers.markdown_inline
      telescope-nvim
      telescope-media-files-nvim
      telescope-fzf-native-nvim
      which-key-nvim
      telekasten-nvim
      nvim-lspconfig
      markdown-preview-nvim
    ];

    extraPackages = with pkgs; [
      ripgrep
      fd
      chafa
    ];

    extraConfig = ''
      set showmatch
      set smartcase
      filetype plugin indent on
      set shiftwidth=2
      syntax on
      filetype plugin on
      set cursorline
    '';

    extraLuaConfig = ''
      vim.g.mapleader = ","

      require("oil").setup()
      local wk = require("which-key")

      local ts = require("telescope")
      ts.load_extension('fzf')
      ts.load_extension('media_files')

    '';
  };
}
