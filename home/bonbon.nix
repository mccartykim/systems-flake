# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    uv
    goose-cli
    claude-code
  ];
  programs = {
    bash.enable = true;
    atuin.enable = true;
    nix-index.enable = true;
    tealdeer.enable = true;
    ripgrep.enable = true;
    zoxide.enable = true;
    eza.enable = true;
    bat.enable = true;
    jujutsu = {
      enable = true;
      settings = {
        user = {
          email = "kimb@kimb.dev";
          name = "Kimberly McCarty";
        };
        ui.diff-formatter = [
          "${pkgs.difftastic}/bin/difft"
          "--color=always"
          "$left"
          "$right"
        ];
      };
    };
  };
  home.stateVersion = "23.05";
}
