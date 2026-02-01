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
    ./modules/ai-tools.nix
  ];

  modules = {
    shell-essentials.enable = true;
    development.enable = true;
    terminal-enhanced = {
      enable = true;
      kitty = true;
    };
    ai-tools.enable = true;
  };

  home.stateVersion = "23.05";

  programs.fish = {
    enable = true;
  };
  programs.atuin = {
    enable = true;
  };
}
