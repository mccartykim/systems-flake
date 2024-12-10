{
  pkgs,
  config,
  lib,
  ...
}: let
  home-config = {
    home.stateVersion = "23.05";
    home.packages = [
      pkgs.atuin
      pkgs.chafa
      pkgs.android-tools
      pkgs.shell-gpt
      pkgs.tealdeer
      pkgs.delta
      pkgs.ripgrep
      pkgs.fd
      pkgs.ffmpeg
      pkgs.wget
      pkgs.aria2
      pkgs.nil
      pkgs.nb
      pkgs.watchman
      pkgs.allure
      pkgs.nerd-fonts.symbols-only
      pkgs.nerd-fonts.blex-mono
      pkgs.terminal-notifier
      pkgs.ripgrep
    ];

    programs.bat.enable = true;
    programs.eza.enable = true;
    programs.eza.icons = "auto";

    programs.fd.enable = true;

    programs.jujutsu.enable = true;
    programs.jujutsu.settings = {
      user = {
        email = "kimberly.mccarty@onepeloton.com";
	name = "Kimberly McCarty";
      };
    };

    programs.yt-dlp.enable = true;
    programs.git = {
      enable = true;
      delta.enable = true;
    };

    programs.zellij = {
      enable = true;
    };

    programs.nix-index.enable = true;

    programs.fzf = {
      enable = true;
      enableFishIntegration = true;
    };

    programs.fish = {
      enable = true;
      plugins = [
        {
          name = "tide";
          src = pkgs.fishPlugins.tide.src;
        }
        {
          name = "fzf";
          src = pkgs.fishPlugins.fzf.src;
        }
        {
          name = "done";
          src = pkgs.fishPlugins.done.src;
        }
        {
          name = "colored-man-pages";
          src = pkgs.fishPlugins.colored-man-pages.src;
        }
        {
          name = "autopair";
          src = pkgs.fishPlugins.autopair.src;
        }
      ];
      # Fish path bug workaround
      shellInit = let
        # This naive quoting is good enough in this case. There shouldn't be any
        # double quotes in the input string, and it needs to be double quoted in case
        # it contains a space (which is unlikely!)
        dquote = str: "\"" + str + "\"";

        makeBinPathList = map (path: path + "/bin");
      in ''
        fish_add_path --move --prepend --path ${lib.concatMapStringsSep " " dquote (makeBinPathList config.environment.profiles)}
        set fish_user_paths $fish_user_paths
      '';
    };
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      extraPackages = with pkgs; [
      	nodejs_22
      ];
      plugins = with pkgs.vimPlugins; [
        nvim-treesitter
        nvim-treesitter-parsers.c
        nvim-treesitter-parsers.cpp
        nvim-treesitter-parsers.nix
        nvim-treesitter-parsers.fish
        nvim-treesitter-parsers.bash
        nvim-treesitter-parsers.git_rebase
        nvim-treesitter-parsers.go
        nvim-treesitter-parsers.groovy
        nvim-treesitter-parsers.kotlin
        nvim-treesitter-parsers.java
        nvim-treesitter-parsers.javascript
        nvim-treesitter-parsers.mermaid
        nvim-treesitter-parsers.python
        oil-nvim
        fzf-lua
        telescope-nvim
        telescope-symbols-nvim
        telekasten-nvim
        markdown-preview-nvim
        vim-markdown-toc
        which-key-nvim
        calendar-vim
        telescope-media-files-nvim
        telescope-fzf-native-nvim
      ];
      extraLuaConfig = ''
              vim.g.mapleader = ","
                     require("oil").setup({
                defaultFileExplorer = true,
              })
              local ts = require('telescope')
              -- ts.load_extension('media_files')
              ts.load_extension('fzf')

             require('telekasten').setup({
        home = vim.fn.expand("~/zettelkasten"), -- Put the name of your notes directory here
             })

              -- Launch panel if nothing is typed after <leader>z
              vim.keymap.set("n", "<leader>z", "<cmd>Telekasten panel<CR>")

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

              local wk = require("which-key")
      '';
      coc = {
        enable = true;

        settings = {
          "languageserver" = {
            "nix" = {
              command = "nil";
              filetypes = ["nix"];
              rootPatterns = ["flake.nix" ".git"];
            };
          };
        };
      };
    };
    programs.atuin = {
      enable = true;
    };
    programs.zoxide.enable = true;
    programs.direnv.enable = true;
  };
in {
  home-manager.users."kimberly.mccarty" = home-config;
}
