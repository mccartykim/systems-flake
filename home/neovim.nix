{ pkgs, home-manager, ... }: {

  
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
      markdown-preview-nvim
    ];

    extraPackages = with pkgs; [
      pkgs.ripgrep 
      pkgs.fd 
      pkgs.chafa 
    ];

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
	 vim.g.mapleader = ","

	 require("oil").setup()
	 local wk = require("which-key")

	 local ts = require("telescope")
	 ts.load_extension('fzf')
	 ts.load_extension('media_files')
	 require("telekasten").setup({
	   home = vim.fn.expand("~/zettelkasten"),
	 });

	 -- Most used functions
        vim.keymap.set("n", "<leader>zf", "<cmd>Telekasten find_notes<CR>")
        vim.keymap.set("n", "<leader>zg", "<cmd>Telekasten search_notes<CR>")
        vim.keymap.set("n", "<leader>zd", "<cmd>Telekasten goto_today<CR>")
        vim.keymap.set("n", "<leader>zz", "<cmd>Telekasten follow_link<CR>")
        vim.keymap.set("n", "<leader>zn", "<cmd>Telekasten new_note<CR>")
        vim.keymap.set("n", "<leader>zc", "<cmd>Telekasten show_calendar<CR>")
        vim.keymap.set("n", "<leader>zb", "<cmd>Telekasten show_backlinks<CR>")
        vim.keymap.set("n", "<leader>zI", "<cmd>Telekasten insert_img_link<CR>")

        -- Call insert link automatically when we start typing a link
        vim.keymap.set("i", "[[", "<cmd>Telekasten insert_link<CR>")


         wk.register(mappings, opts)
    '';
  };
}
