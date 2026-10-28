# Emulator stack for the Steam Deck. Keys/firmware/ROMs live under
# ~/.local/share/<emu>/ and are not managed by Nix.
{
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages =
    [
      # Switch — eden-nightly built from upstream master with steamdeck profile (znver2 + LTO).
      # The pinned June nightly predates GCC 16 / fmt 12 / httplib 0.58; upstream fixed the
      # resulting includes and API calls in master. Backport them until eden-nightly-flake is
      # bumped (its cpmfiles have diverged, so a bump needs re-verification).
      (inputs.eden-nightly-flake.packages.x86_64-linux.eden-nightly-steamdeck.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            # All three fixed upstream after the pinned nightly; backport them here.
            sed -i '1i #include <cstring>' src/common/dynamic_library.cpp
            substituteInPlace src/common/net/net.cpp src/yuzu/updater/update_dialog.cpp \
              --replace-fail 'response.headers.contains("content-type")' \
              'response.has_header("content-type")'
            substituteInPlace \
              src/common/settings_setting.h src/common/settings.cpp src/common/time_zone.cpp \
              src/yuzu/startup_checks.cpp src/yuzu/configuration/shared_widget.cpp \
              --replace-fail '#include <fmt/core.h>' '#include <fmt/format.h>'
          '';
      }))
    ]
    ++ (with pkgs; [
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
