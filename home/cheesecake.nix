{pkgs, ...}: {
  home.packages = with pkgs; [
    neovim
    firefox
    btop
    ghostty
  ];

  imports = [
    ./modules/development.nix
    ./modules/shell-essentials.nix
  ];

  modules = {
    shell-essentials.enable = true;
    development.enable = true;
  };

  home.stateVersion = "23.05";

  programs.fish = {
    enable = true;
  };
  programs.atuin = {
    enable = true;
  };
}
