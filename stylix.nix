{
  stylix,
  pkgs,
  ...
}: {
  stylix.fonts = {
    monospace = {
      package = pkgs.ibm-plex;
      name = "IBM Plex Mono";
    };

    emoji = {
      package = pkgs.nerdfonts.override {fonts = ["Noto"];};
      name = "Noto Color Emoji";
    };
  };
}
