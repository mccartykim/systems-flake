# Emulator stack for the Steam Deck. Keys/firmware/ROMs live under
# ~/.local/share/<emu>/ and are not managed by Nix.
{pkgs, ...}: let
  # Eden built from upstream master with the steamdeck profile (znver2 + LTO
  # + sdl2_steamdeck CPM dep). Shared package; see ../../pkgs/eden-master/.
  eden-master = pkgs.callPackage ../../pkgs/eden-master {profile = "steamdeck";};

  # Eden nightly via DwarFS-extracted AppImage (kept around in case we need to
  # diff master-from-source vs the pre-built nightly).
  eden-nightly = pkgs.callPackage ./eden-nightly.nix {};
in {
  environment.systemPackages = with pkgs; [
    # Switch
    eden-master
    eden-nightly
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
    flycast # Dreamcast (also available as a libretro core via retroarch-full)

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
