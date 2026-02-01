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
    ./modules/terminal-enhanced.nix
  ];

  modules = {
    shell-essentials.enable = true;
    development.enable = true;
    terminal-enhanced = {
      enable = true;
      kitty = true;
    };
  };

  home.stateVersion = "23.05";

  programs.fish = {
    enable = true;
  };
  programs.atuin = {
    enable = true;
  };
}
