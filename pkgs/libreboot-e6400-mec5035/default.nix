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

  # We do NOT use the standard `patches` attribute because nic3-14159's
  # branch was based on pristine upstream coreboot, while lbmk's release
  # tarball ships coreboot with ~40 of lbmk's own patches already applied.
  # Plain `patch -p1` can't reconcile the drift. Instead we use git am
  # --3way in postPatch, which uses the patch's blob hashes to find the
  # original content and merge intelligently.
  mec5035Patches = ./patches;

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
  #
  # Also: apply nic3-14159's mec5035-acpi patches via `git am --3way`
  # inside src/coreboot/default. The 3-way merge resolves the drift
  # between his branch base and lbmk's modified coreboot.
  postPatch = ''
    chmod -R u+w .
    rm -f lock
    export HOME=$NIX_BUILD_TOP
    git config --global user.email "nix@build.local"
    git config --global user.name "nix-build"

    pushd src/coreboot/default
    git init -q -b main .
    git add -A
    git commit -q -m "lbmk vendored coreboot baseline"
    for p in ${finalAttrs.mec5035Patches}/*.patch; do
      echo "==> git am --3way $(basename "$p")"
      git am --3way --keep-non-patch "$p" || {
        echo "FAILED: $p"
        echo "---- conflict files ----"
        git status
        exit 1
      }
    done
    popd
  '';

  # Point coreboot's makefile at the nixpkgs-built crossgcc instead of
  # rebuilding the toolchain (which is hours of work).
  XGCCPATH = "${coreboot-toolchain.i386}/bin";

  enableParallelBuilding = true;

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
