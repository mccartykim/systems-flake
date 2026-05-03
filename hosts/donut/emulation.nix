# Emulator stack for the Steam Deck. Keys/firmware/ROMs live under
# ~/.local/share/<emu>/ and are not managed by Nix.
{pkgs, ...}: let
  # Eden built from upstream master, pre-fetching cpmfile.json deps so the
  # build is sandbox-friendly. See eden-master.nix for the bump procedure.
  eden-master = pkgs.callPackage ./eden-master.nix {};

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
