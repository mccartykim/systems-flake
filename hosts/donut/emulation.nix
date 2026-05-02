# Emulator stack for the Steam Deck. Keys/firmware/ROMs live under
# ~/.local/share/<emu>/ and are not managed by Nix.
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # Switch
    eden
    ryubing

    # Sony
    pcsx2
    rpcs3

    # Nintendo
    dolphin-emu
    cemu
    azahar
    melonds

    # Sega/handheld/misc
    ppsspp
    mesen

    # Catch-all + PS1 via Swanstation core
    retroarch-full
  ];

  # Allow running AppImages directly (Eden ships an AppImage; useful for
  # one-off emulator builds outside nixpkgs).
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # Flatpak for ES-DE frontend and Steam ROM Manager (neither in nixpkgs).
  services.flatpak.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
  };
}
