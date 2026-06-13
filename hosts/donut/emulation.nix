# Emulator stack for the Steam Deck. Keys/firmware/ROMs live under
# ~/.local/share/<emu>/ and are not managed by Nix.
{pkgs, inputs, ...}: {
  environment.systemPackages = [
    # Switch — eden-nightly built from upstream master with steamdeck profile (znver2 + LTO)
    inputs.eden-nightly-flake.packages.x86_64-linux.eden-nightly-steamdeck
  ] ++ (with pkgs; [
    ryubing

    # Sony
    pcsx2
    # rpcs3 — BROKEN: GLEW 2.3.1 removes GLX symbols that rpcs3 links against
    # (undefined reference to __glewXSwapIntervalEXT). See nixpkgs#427693,
    # rpcs3#16819. Re-enable once nixpkgs patches rpcs3 for GLEW 2.3+.

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
  ]);

  # Allow running AppImages directly (useful for one-off emulator builds
  # outside nixpkgs).
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
  };
}