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
      package = pkgs.noto-fonts-monochrome-emoji;
      name = "Noto Emoji";
    };
  };
}
