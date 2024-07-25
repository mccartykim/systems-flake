{
  config,
  pkgs,
  stylix,
  ...
}: {
  stylix.enable = true;
  stylix.image = ./marsh-flower.jpg;
  stylix.polarity = "dark";
  stylix.fonts = {
    sizes = {
      desktop = 14;
      terminal = 14;
    };
  };
}
