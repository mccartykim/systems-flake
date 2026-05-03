# Eden nightly Switch emulator, extracted from upstream's DwarFS AppImage.
#
# Bump procedure:
#   1. Get latest from `eden-ci/nightly` releases on git.eden-emu.dev
#   2. Update commit + timestamp + hash below
#   3. nix flake check && deploy
{
  stdenv,
  lib,
  fetchurl,
  dwarfs,
  makeWrapper,
}: let
  commit = "7d0e79335e";
  timestamp = "1777747568";
  publishedDate = "2026-05-02";
in
  stdenv.mkDerivation {
    pname = "eden-nightly";
    version = "0-unstable-${publishedDate}-${commit}";

    src = fetchurl {
      url = "https://nightly.eden-emu.dev/v${timestamp}.${commit}/Eden-Linux-${commit}-steamdeck-gcc-standard.AppImage";
      hash = "sha256-0X6NhyBEfJoGZYHGaWOqC2/yr0kWk2wUN0FiMqfcvtU=";
    };

    nativeBuildInputs = [dwarfs makeWrapper];

    dontUnpack = true;
    dontConfigure = true;

    # The AppImage's payload (a DwarFS image) starts at byte offset 1454544.
    # Slice it out and let dwarfsextract turn it into a normal directory.
    buildPhase = ''
      runHook preBuild
      dd if=$src of=eden.dwarfs bs=1M iflag=skip_bytes skip=1454544 status=none
      mkdir -p root
      dwarfsextract -i eden.dwarfs -o root --num-workers $NIX_BUILD_CORES
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/libexec/eden-nightly
      cp -r root/. $out/libexec/eden-nightly/
      chmod +x $out/libexec/eden-nightly/AppRun

      mkdir -p $out/bin
      makeWrapper $out/libexec/eden-nightly/AppRun $out/bin/eden-nightly

      install -Dm644 root/dev.eden_emu.eden.svg \
        $out/share/icons/hicolor/scalable/apps/eden-nightly.svg

      mkdir -p $out/share/applications
      cat > $out/share/applications/eden-nightly.desktop <<EOF
      [Desktop Entry]
      Type=Application
      Name=Eden (nightly)
      GenericName=Switch Emulator
      Comment=Nintendo Switch emulator (eden-emu nightly ${commit})
      Exec=$out/bin/eden-nightly %f
      Icon=eden-nightly
      Terminal=false
      Categories=Game;Emulator;
      MimeType=application/x-nx-nca;application/x-nx-nro;application/x-nx-nso;application/x-nx-nsp;application/x-nx-xci;
      EOF

      runHook postInstall
    '';

    meta = {
      description = "Nintendo Switch emulator (eden nightly, DwarFS-extracted)";
      homepage = "https://eden-emu.dev/";
      mainProgram = "eden-nightly";
      license = lib.licenses.gpl3Plus;
      platforms = ["x86_64-linux"];
    };
  }
