{
  config,
  pkgs,
  stylix,
  ...
}: {
  stylix.enable = true;
  stylix.image = ./marsh-flower.jpg;
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/monokai.yaml";
  stylix.fonts = {
    sizes = {
      desktop = 14;
      terminal = 14;
    };
  };
}
