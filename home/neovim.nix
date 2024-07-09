{ pkgs, home-manager, ... }: {

  
  programs.neovim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [
      oil-nvim
      nvim-treesitter
      nvim-treesitter-parsers.nix
      nvim-treesitter-parsers.html
      nvim-treesitter-parsers.markdown
      nvim-treesitter-parsers.markdown_inline
      telescope-nvim
      telescope-media-files-nvim
      which-key-nvim
      telekasten-nvim
    ] ++ [  ];

    defaultEditor = true;

    extraConfig = ''
      set showmatch
      set smartcase
      filetype plugin indent on
      set shiftwidth=2
      syntax on " lol it can't be necessary
      filetype plugin on
      set cursorline
    '';

    extraLuaConfig = ''
	 require("oil").setup()
	 local wk = require("which-key")
         wk.register(mappings, opts)
	 require("telekasten").setup({
	   home = vim.fn.expand("~/zettelkasten"),
	 });
    '';
  };

  home.packages = with pkgs; [ pkgs.ripgrep pkgs.fd pkgs.chafa ];
}
