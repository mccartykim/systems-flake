# Libreboot 26.01rev1 for the Dell Latitude E6400, patched with
# nic3-14159's `mec5035-acpi` branch (13 commits) to fix the missing
# battery / AC adapter / brightness Fn-key ACPI support that ships
# blank in upstream coreboot's `src/mainboard/dell/e6400/acpi/ec.asl`.
#
# Background: the original E6400 coreboot port (also by nic3-14159)
# shipped an EC stub — battery/AC/brightness all return "not present"
# under Linux. He wrote the fix later on a personal branch but never
# pushed it to coreboot Gerrit, so it never landed in libreboot. The
# 13 patches under ./patches/ are `git format-patch 211526ff..mec5035-acpi`
# from his fork pinned at 9e3a7e58dd194a34cc86bca4cc0a11305c62b157.
#
# Output: a single ROM file at $out/seagrub_e6400_4mb_libgfxinit_corebootfb_usqwerty.rom,
# ready to be GbE-spliced (nvmutil + ifdtool) and internal-flashed via
# dell-flash-unlock + flashprog.
{
  stdenv,
  lib,
  fetchurl,
  coreboot-toolchain,
  autoconf,
  automake,
  libtool,
  m4,
  cmake,
  python3,
  pkg-config,
  git,
  gnumake,
  zlib,
  openssl,
  bison,
  flex,
  ncurses,
  gnused,
  gnugrep,
  gawk,
  xz,
  gnutar,
  coreutils,
  which,
  perl,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "libreboot-e6400-mec5035";
  version = "26.01rev1+mec5035-acpi";

  src = fetchurl {
    url = "https://mirror.math.princeton.edu/pub/libreboot/stable/26.01rev1/libreboot-26.01rev1_src.tar.xz";
    hash = "sha512-3fyK6lM2TdWFWJyEgcQRrMA+8c6mZLCM89JVXSEzWp6NDM61i0yeRUKfoG575sQYint5g/KS/ABS0Nn33jUZ4Q==";
  };

  # A single consolidated diff between lbmk's coreboot tree (as shipped
  # in 26.01rev1) and nic3-14159's `mec5035-acpi` branch tip
  # (9e3a7e58dd194a34cc86bca4cc0a11305c62b157), restricted to the
  # src/ec/dell/mec5035/** and src/mainboard/dell/gm45_latitude/**
  # subtrees that matter for E6400. Replaces the 13 separate format-patch
  # commits because lbmk's coreboot has drifted enough (lbmk-side patches
  # like 0014/0021/0038/0039 already apply some of the same changes) that
  # the upstream commits no longer apply cleanly.
  patches = [./patches/0001-mec5035-acpi-consolidated.patch];
  patchFlags = ["-p1" "-d" "src/coreboot/default"];

  nativeBuildInputs = [
    coreboot-toolchain.i386
    autoconf
    automake
    libtool
    m4
    cmake
    python3
    pkg-config
    git
    gnumake
    bison
    flex
    ncurses
    gnused
    gnugrep
    gawk
    xz
    gnutar
    coreutils
    which
    perl
  ];

  buildInputs = [zlib openssl];

  # lbmk's mk script wants:
  #   - a writable tree (the source tarball ships a read-only `lock` file)
  #   - a git identity (it auto-inits a git repo for change tracking)
  postPatch = ''
    chmod -R u+w .
    rm -f lock
    export HOME=$NIX_BUILD_TOP
    git config --global user.email "nix@build.local"
    git config --global user.name "nix-build"

    # lbmk's scripts use #!/usr/bin/env sh and similar shebangs that
    # don't exist in the build sandbox.
    patchShebangs --build mk include script util
  '';

  # Point coreboot's makefile at the nixpkgs-built crossgcc instead of
  # rebuilding the toolchain (which is hours of work).
  XGCCPATH = "${coreboot-toolchain.i386}/bin";

  enableParallelBuilding = true;

  # lbmk is its own build orchestrator. mkDerivation's stdenv would
  # otherwise auto-run cmake (because cmake is in nativeBuildInputs for
  # lbmk's uefitool subdep) and try to configure us — skip that.
  dontUseCmakeConfigure = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    # lbmk's -b flag triggers a build; second arg is the project, third is
    # the board target. This builds coreboot for e6400_4mb only.
    ./mk -b coreboot e6400_4mb
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    # Pick the seagrub corebootfb usqwerty variant (matches what's currently
    # flashed on creme). The DO_NOT_FLASH prefix is stripped at this stage.
    install -Dm644 \
      bin/e6400_4mb/*seagrub_e6400_4mb_libgfxinit_corebootfb_usqwerty.rom \
      $out/seagrub_e6400_4mb_libgfxinit_corebootfb_usqwerty.rom
    # Also keep the rest of the e6400_4mb output tree for inspection.
    cp -r bin/e6400_4mb $out/bin-tree
    runHook postInstall
  '';

  meta = with lib; {
    description = "Libreboot 26.01rev1 for Dell Latitude E6400 with nic3-14159's mec5035-acpi patches (battery + brightness Fn keys)";
    homepage = "https://libreboot.org/";
    license = licenses.gpl3Plus;
    platforms = ["x86_64-linux"];
    maintainers = [];
  };
})
