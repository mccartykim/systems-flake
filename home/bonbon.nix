
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
  ];
  programs.atuin.enable = true;
  programs.nix-index.enable = true;
  programs.tealdeer.enable = true;
  programs.ripgrep.enable = true;
  programs.zoxide.enable = true;
  programs.jujutsu = {
    enable = true;
    settings = {
      user = {
	email = "kimb@kimb.dev";
	name = "Kimberly McCarty";
      };
    };
  };
  home.stateVersion = "23.05";
}
