{ pkgs, home-manager, ... }: {

  programs.neovim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [
      oil-nvim
      nvim-treesitter-parsers.nix
      nvim-treesitter-parsers.html
      nvim-treesitter-parsers.markdown
      nvim-treesitter-parsers.markdown_inline
    ];

    extraLuaConfig = ''
	 require("oil").setup()
    '';
  };

}
