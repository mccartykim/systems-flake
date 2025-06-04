# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import other home-manager modules here
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule

    # You can also split up your configuration and import pieces of it here:
    ./default.nix
    ./neovim.nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
      # Workaround for https://github.com/nix-community/home-manager/issues/2942
      allowUnfreePredicate = _: true;
    };
  };

  home = {
    username = "kimb";
    homeDirectory = "/home/kimb";
  };

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  home.packages = with pkgs; [
    nil
    nh
    umu-launcher
    goose-cli
    claude-code
  ];
  programs.jujutsu.enable = true;
  programs.jujutsu.settings = {
    user = {
      email = "kimb@kimb.dev";
      name = "Kimberly McCarty";
    };
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  programs.zoxide.enable = true;
  programs.fish.enable = true;
  programs.fish.functions = {
    fish_jj_prompt = ''
      # Is jj installed?
      if not command -sq jj
          return 1
      end

      # Are we in a jj repo?
      if not jj root --quiet --no-pager &>/dev/null
          return 1
      end

      # Generate prompt
      jj log --ignore-working-copy --no-pager --no-graph --color always -r @ -T '
          surround(
              " (",
              ")",
              separate(
                  " ",
                  bookmarks.join(", "),
                  coalesce(
                      surround(
                          "\"",
                          "\"",
                          if(
                              description.first_line().substr(0, 24).starts_with(description.first_line()),
                              description.first_line().substr(0, 24),
                              description.first_line().substr(0, 23) ++ "…"
                          )
                      ),
                      "(no desc)"
                  ),
                  change_id.shortest(),
                  commit_id.shortest(),
                  if(conflict, "(conflict)"),
                  if(empty, "(empty)"),
                  if(divergent, "(divergent)"),
                  if(hidden, "(hidden)"),
              )
          )
      '
    '';
    fish_vcs_prompt = ''
            # Defined in /nix/store/j2qz2d900y518k2hq6myl60g2vyh7l19-fish-4.0.1/share/fish/functions/fish_vcs_prompt.fish @ line 1
            function fish_vcs_prompt --description 'Print all vcs prompts'
            # If a prompt succeeded, we assume that it's printed the correct info.
            # This is so we don't try svn if git already worked.
      	fish_jj_prompt $argv
      	or fish_git_prompt $argv
      	or fish_hg_prompt $argv
      	or fish_fossil_prompt $argv
          # The svn prompt is disabled by default because it's quite slow on common svn repositories.
          # To enable it uncomment it.
          # You can also only use it in specific directories by checking $PWD.
          # or fish_svn_prompt
      end
    '';
  };
  programs.atuin.enable = true;

  programs.tmux = {
    enable = true;
    mouse = true;
    keyMode = "vi";
  };

  programs.zellij.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
