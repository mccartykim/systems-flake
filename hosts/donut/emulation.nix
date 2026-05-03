# Emulator stack for the Steam Deck. Keys/firmware/ROMs live under
# ~/.local/share/<emu>/ and are not managed by Nix.
{pkgs, ...}: let
  # nixpkgs ships eden 0.1.1; bump to upstream 0.2.0-rc2 (released 2026-03-16).
  # Drop the aarch64-only fastmem patch — the Deck is x86_64 and the patch
  # targets 0.1.x source paths.
  eden-latest = pkgs.eden.overrideAttrs (old: rec {
    version = "0.2.0-rc2";
    src = pkgs.fetchFromGitea {
      domain = "git.eden-emu.dev";
      owner = "eden-emu";
      repo = "eden";
      tag = "v${version}";
      hash = "sha256-keLkB5qeQch+tM2J6zVh9oQGhP5TuxItqrZRN24apJw=";
    };
    patches = [];
    doCheck = false;
    # 0.2.x adds a Qt6Charts dependency (frametime/FPS overlay).
    buildInputs = old.buildInputs ++ [pkgs.qt6.qtcharts];
  });
in {
  environment.systemPackages = with pkgs; [
    # Switch
    eden-latest
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
